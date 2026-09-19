#!/usr/bin/env python3
"""Generate machine- and human-readable integration evidence for one
universe revision: reports/integration/<sha>/{manifest.json,components.json,
checks.json,actor-matrix.json,replay.json,packages.json,summary.org}.

Only facts gathered from the real commands are recorded. Secrets never
enter reports. Transient large artifacts belong to CI storage, not here.

Usage: python3 scripts/report.py [--checks-dir facts] [--out reports/integration]
"""
import argparse
import datetime
import json
import os
import subprocess
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))


def git(args):
    return subprocess.run(
        ["git", "-C", ROOT] + args, capture_output=True, text=True,
        check=False).stdout.strip()


def components():
    out = []
    for line in git(["submodule", "status"]).splitlines():
        parts = line.split()
        if not parts:
            continue
        sha = parts[0].lstrip("+-")
        path = parts[1] if len(parts) > 1 else "?"
        out.append({"component": os.path.basename(path), "path": path,
                    "sha": sha})
    return out


def read_checks(checks_dir):
    path = os.path.join(checks_dir, "checks.json")
    if os.path.exists(path):
        with open(path) as f:
            return json.load(f)
    return {}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--checks-dir", default="facts")
    ap.add_argument("--out", default=os.path.join(
        ROOT, "reports", "integration"))
    args = ap.parse_args()

    sha = git(["rev-parse", "HEAD"]) or "unknown"
    outdir = os.path.join(args.out, sha)
    os.makedirs(outdir, exist_ok=True)

    comps = components()
    checks = read_checks(args.checks_dir)

    manifest = {
        "universe_sha": sha,
        "generated_at": datetime.datetime.now(datetime.timezone.utc)
                          .isoformat(),
        "component_count": len(comps),
        "component_shas": {c["component"]: c["sha"] for c in comps},
    }
    with open(os.path.join(outdir, "manifest.json"), "w") as f:
        json.dump(manifest, f, indent=2, sort_keys=True)

    with open(os.path.join(outdir, "components.json"), "w") as f:
        json.dump(comps, f, indent=2)

    with open(os.path.join(outdir, "checks.json"), "w") as f:
        json.dump(checks, f, indent=2, sort_keys=True)

    for name, default in (("actor-matrix.json", {"status": "not-run"}),
                          ("replay.json", {"status": "not-run"}),
                          ("packages.json", {"status": "not-run"}),
                          ("deployment.json", {"status": "not-run"})):
        src = os.path.join(args.checks_dir, name)
        if os.path.exists(src):
            with open(src) as f:
                data = json.load(f)
        else:
            data = default
        with open(os.path.join(outdir, name), "w") as f:
            json.dump(data, f, indent=2)

    green = [k for k, v in checks.items() if v == "green"]
    red = [k for k, v in checks.items() if v == "red"]
    lines = [
        "# Integration report — universe "
        f"[[https://git.starintel.actor/nsaspy/starintel-universe"
        f"/src/commit/{sha}][{sha[:12]}]]",
        "",
        f"Generated: {manifest['generated_at']}",
        f"Components pinned: {len(comps)}",
        "",
        "* Checks",
        "",
        "| check | status |",
        "|-------+--------|",
    ]
    for k in sorted(checks):
        lines.append(f"| {k} | {checks[k]} |")
    lines += [
        "",
        f"Green: {len(green)}  Red: {len(red)}",
        "",
        "* Component pins",
        "",
        "| component | revision |",
        "|-----------+----------|",
    ]
    for c in comps:
        lines.append(f"| {c['component']} | {c['sha'][:12]} |")
    with open(os.path.join(outdir, "summary.org"), "w") as f:
        f.write("\n".join(lines) + "\n")

    print(outdir)
    return 1 if red else 0


if __name__ == "__main__":
    sys.exit(main())
