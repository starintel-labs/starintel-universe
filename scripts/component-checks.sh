#!/usr/bin/env bash
# Run each component's NATIVE test/build interfaces at their pinned revisions.
# Never replaces component tests; discovers and invokes the real commands.
# Usage: scripts/component-checks.sh [quick]
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"

QUICK="${1:-}"
FAIL=0

run() {
  local name="$1"; shift
  local dir="$1"; shift
  echo "=== [component] $name"
  if [ ! -d "$dir" ]; then echo "SKIP (missing): $dir"; return 0; fi
  ( cd "$dir" && "$@" )
  local rc=$?
  if [ $rc -ne 0 ]; then echo "FAIL($rc): $name"; FAIL=1; else echo "PASS: $name"; fi
}

# ---- prolog-rlm: native suite ---------------------------------------
run prolog-rlm components/prolog-rlm bash -c '
  swipl -q -s test/check_runtime.pl &&
  swipl -q -s test/load_all.pl &&
  swipl -q -s test/run_tests.pl'

# ---- star-kb: native suite -------------------------------------------
run star-kb components/star-kb bash -c '
  python3 -m py_compile scripts/*.py &&
  python3 -m unittest discover -s tests -p "test_*.py" -v &&
  python3 scripts/validate-docs.py'

# ---- star-lang: native flake check (skip in quick mode; heavy) --------
if [ "$QUICK" != "quick" ]; then
  run star-lang components/star-lang nix flake check --no-build
fi

# ---- star-cl: native flake check -------------------------------------
if [ "$QUICK" != "quick" ]; then
  run star-cl components/star-cl nix flake check --no-build
fi

# ---- zara / zara-plugins: native flake check -------------------------
if [ "$QUICK" != "quick" ]; then
  run zara components/zara nix flake check --no-build
  run zara-plugins components/zara-plugins nix flake check --no-build
fi

# ---- quasar: native static checks (npm) -------------------------------
run quasar components/quasar bash -c 'npm run check'

# ---- quasar-ui: native checks (npm) ------------------------------------
run quasar-ui components/quasar-ui bash -c 'npm run check'

exit $FAIL
