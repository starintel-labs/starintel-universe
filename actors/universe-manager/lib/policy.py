"""Control-plane bridge for the universe-manager actor.

Every policy decision is made by the tracked Prolog control plane
(.prolog/*.pl) invoked through swipl; this module only gathers facts,
renders terms safely, and maps exit codes. No LLM, no network policy.

Invocation model
----------------
The canonical form ``swipl -q .prolog/cli.pl <cmd> <args...>`` cannot
carry facts today: cli.pl's own directive fails when a facts directory
exists (see lib/facts_shim.pl). run_swipl/2 therefore drives the very
same cli.pl dispatch with the argv injected up front:

    swipl -q -f none \
        -g "consult([<universe.pl>, <facts_shim.pl>]),
             set_prolog_flag(argv, [<cmd>, <args...>]),
             consult(<cli.pl>)" \
        -t halt

run/1 inside cli.pl is still the only decision path, and every swipl
process runs with cwd = repository root as required.

Quoting rules (security-relevant)
---------------------------------
cli.pl parses argv elements with atom_to_term/3, so term text matters:

* digit-leading SHAs (``5f63...``) are invalid Prolog tokens — bare they
  raise syntax errors (cli exits 2);
* uppercase-leading SHAs (``Abc0...``) parse as *variables*, which would
  make known_pin/2 unify with any pin (false allow).

prolog_term_escape/1 therefore always renders 40-hex SHAs as
single-quoted atoms, in goal text and in generated facts files alike.
"""

from __future__ import annotations

import os
import re
import subprocess
import sys

SAFE_ATOM_RE = re.compile(r"^[a-z][a-zA-Z0-9_]*$")
SHA_RE = re.compile(r"^[0-9a-fA-F]{40}$")
CHECK_STATUSES = ("green", "red", "skipped", "pending")
ACTOR_LIB_DIR = os.path.dirname(os.path.abspath(__file__))


def prolog_atom(value: str) -> str:
    """Render a python string as Prolog atom *term text* (safe quoting)."""
    if SHA_RE.match(value):
        # Always quote SHAs: digit-leading ones are syntax errors and
        # uppercase-leading ones would parse as variables downstream.
        return "'" + value + "'"
    if SAFE_ATOM_RE.match(value):
        return value
    return "'" + value.replace("\\", "\\\\").replace("'", "\\'") + "'"


def prolog_quoted_atom(value: str) -> str:
    """Render a string as a quoted atom regardless of its shape."""
    return "'" + value.replace("\\", "\\\\").replace("'", "\\'") + "'"


def prolog_term_escape(value):
    """Render python values as the c(Component, From, To) Prolog syntax
    the CLI expects.

    * str  -> atom term text (SHAs always single-quoted, see module doc)
    * dict -> c(Component, From, To)   (keys: component/from/to)
    * list/tuple -> Prolog list of the rendered elements
    """
    if isinstance(value, str):
        return prolog_atom(value)
    if isinstance(value, dict):
        try:
            component = value["component"]
            from_sha = value["from"]
            to_sha = value["to"]
        except KeyError as exc:
            raise TypeError(f"change dict missing key: {exc}") from exc
        return "c({}, {}, {})".format(
            prolog_term_escape(component),
            prolog_term_escape(from_sha),
            prolog_term_escape(to_sha),
        )
    if isinstance(value, (list, tuple)):
        return "[" + ",".join(prolog_term_escape(item) for item in value) + "]"
    raise TypeError(f"cannot render {type(value).__name__} as a Prolog term")


def build_changeset(changes):
    """[change-dict, ...] -> '[c(C1,F1,T1),c(C2,F2,T2)]' term text."""
    return prolog_term_escape(list(changes))


def _swipl_binary() -> str:
    binary = os.environ.get("SWIPL_BIN", "swipl")
    return binary


def find_repo_root(start: str | None = None) -> str:
    """Absolute path of the git worktree root containing *start* (cwd)."""
    proc = subprocess.run(
        ["git", "rev-parse", "--show-toplevel"],
        cwd=start or os.getcwd(),
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    if proc.returncode != 0:
        raise RuntimeError("not inside a git worktree: " + proc.stderr.strip())
    return os.path.abspath(proc.stdout.strip())


def run_swipl(args, cwd):
    """Run one cli.pl command (args e.g. ["candidate", C, From, To]).

    Returns (rc, stdout). rc: 0 = policy YES, 1 = policy NO,
    2 = usage/policy error. stderr is echoed for operator visibility.
    """
    root = find_repo_root(cwd)
    universe = os.path.join(root, ".prolog", "universe.pl")
    cli = os.path.join(root, ".prolog", "cli.pl")
    shim = os.path.join(ACTOR_LIB_DIR, "facts_shim.pl")
    for path in (universe, cli, shim):
        if not os.path.isfile(path):
            raise RuntimeError(f"control-plane file missing: {path}")

    argv_terms = []
    for arg in args:
        text = str(arg)
        if SHA_RE.match(text):
            # atom_to_term re-parses the atom TEXT, so a sha must travel as
            # an atom whose text is 'quoted' (bare digit-leading shas are
            # syntax errors, uppercase-leading ones become variables).
            term_text = prolog_atom(text)
        else:
            term_text = text
        argv_terms.append(prolog_quoted_atom(term_text))
    goal = "consult([{}, {}]), set_prolog_flag(argv, [{}]), consult({})".format(
        prolog_quoted_atom(universe),
        prolog_quoted_atom(shim),
        ",".join(argv_terms),
        prolog_quoted_atom(cli),
    )
    env = dict(os.environ)
    env["STARINTEL_UNIVERSE_FACTS"] = os.path.join(root, "facts")
    proc = subprocess.run(
        [_swipl_binary(), "-q", "-f", "none", "-g", goal, "-t", "halt"],
        cwd=root,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        env=env,
    )
    if proc.stderr:
        sys.stderr.write(proc.stderr)
    if proc.returncode == 0 and "Goal (directive) failed" in proc.stderr:
        # cli.pl's argv dispatch failed (e.g. a consult blew up inside a
        # command); swipl would still exit 0 — never let that read as YES.
        return 2, proc.stdout
    return proc.returncode, proc.stdout


def query_control_plane(goal_body, cwd):
    """Run a read-only goal against the static control plane (no facts).

    Returns (rc, stdout); rc != 0 means the goal failed or threw.
    """
    root = find_repo_root(cwd)
    universe = os.path.join(root, ".prolog", "universe.pl")
    if not os.path.isfile(universe):
        raise RuntimeError(f"control-plane file missing: {universe}")
    goal = "consult({}), ({}), halt".format(prolog_quoted_atom(universe), goal_body)
    proc = subprocess.run(
        [_swipl_binary(), "-q", "-f", "none", "-g", goal, "-t", "halt"],
        cwd=root,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    return proc.returncode, proc.stdout


def parse_registry(cwd):
    """component(Name) x component(Name, Path, _) x upstream/3 -> mappings.

    Returns (path_to_components, component_to_upstream_branch).
    """
    rc, out = query_control_plane(
        "forall(component(C, P, _), format('~w ~w~n', [C, P])),"
        " forall(upstream(C, _, B), format('branch ~w ~w~n', [C, B]))",
        cwd,
    )
    if rc != 0:
        raise RuntimeError("control-plane registry query failed")
    path_to_components: dict[str, list[str]] = {}
    component_branch: dict[str, str] = {}
    for line in out.splitlines():
        line = line.strip()
        if not line:
            continue
        if line.startswith("branch "):
            _, component, branch = line.split(" ", 2)
            component_branch.setdefault(component, branch)
            continue
        component, path = line.split(" ", 1)
        path_to_components.setdefault(path, []).append(component)
    return path_to_components, component_branch


def query_dependents(component, cwd):
    """Dependents of a component per the tracked dependency graph."""
    rc, out = query_control_plane(
        "dependents({}, Ds), format('~q~n', [Ds])".format(prolog_atom(component)),
        cwd,
    )
    if rc != 0:
        raise RuntimeError(f"dependents query failed for {component}")
    line = out.strip().splitlines()[-1] if out.strip() else "[]"
    body = line.strip()[1:-1] if line.startswith("[") and line.endswith("]") else ""
    return [item for item in body.split(",") if item.strip()]


def write_checks_facts(mapping, path):
    """Write {check: status} mapping as check(Name, Status). facts."""
    lines = ["% machine-generated by universe-manager gate; no secrets"]
    for name in sorted(mapping):
        status = str(mapping[name])
        if status not in CHECK_STATUSES:
            raise ValueError(f"invalid check status {status!r} for {name!r}")
        lines.append("check({}, {}).".format(prolog_atom(name), prolog_atom(status)))
    with open(path, "w", encoding="utf-8") as handle:
        handle.write("\n".join(lines) + "\n")


def parse_denials(stdout):
    """cli.pl merge_denial output (one ~q term per line) -> list of strings."""
    return [line.strip() for line in stdout.splitlines() if line.strip()]


def append_fact_lines(path, lines):
    """Append fact lines to a file, skipping lines already present."""
    existing: set[str] = set()
    if os.path.isfile(path):
        with open(path, encoding="utf-8") as handle:
            existing = {line.strip() for line in handle if line.strip()}
    fresh = [line for line in lines if line.strip() and line.strip() not in existing]
    if not fresh:
        return
    with open(path, "a", encoding="utf-8") as handle:
        for line in fresh:
            handle.write(line.rstrip("\n") + "\n")
