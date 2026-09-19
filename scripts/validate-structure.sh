#!/usr/bin/env bash
# Structural validation of the universe repository.
# Runs as a Nix check and in CI before any heavy build.
set -euo pipefail
cd "$(git rev-parse --show-toplevel 2>/dev/null || echo .)"

fail() { echo "STRUCTURE-FAIL: $*" >&2; exit 1; }

# 1. .gitmodules paths must match registered components
mapfile -t gm_paths < <(grep '^\s*path = ' .gitmodules | sed 's/.*= //')
[ "${#gm_paths[@]}" -ge 10 ] || fail "expected >=10 submodules, got ${#gm_paths[@]}"

# 2. every submodule must be initialized — only meaningful in a full
#    recursive checkout (the Nix sandbox check copies the tree without
#    submodule contents).
if [ -e components/zara/.git ]; then
  git submodule status >/dev/null || fail "submodule status failed"
  for p in "${gm_paths[@]}"; do
    [ -d "$p/.git" ] || fail "submodule not initialized: $p"
  done
else
  echo "note: sandboxed copy without submodule contents; skipping init checks"
fi

# 3. no secrets in tracked files (cheap heuristic gate; CI adds gitleaks)
! git grep -lEi '(api[_-]?key|secret|password|token)\s*=\s*["'"'"'][A-Za-z0-9_\-]{16,}' \
  -- . ':!*.lock' ':!*lock.json' 2>/dev/null | grep -v -E 'docs|README|\.org|\.md' \
  || fail "possible secret committed (see gitleaks report)"

# 4. XDG hygiene: no shipped runtime writes to ~/.foo outside XDG trees.
#    $HOME/.config, $HOME/.local/*, $HOME/.cache ARE the XDG fallbacks and
#    are allowed; anything else dot-prefixed in $HOME is a violation.
if grep -rn '\$HOME/\.' distro/ --include='*.nix' --include='*.sh' --include='*.toml' 2>/dev/null \
  | grep -vE '\$HOME/\.(config|local/(share|state)|cache)'; then
  fail "non-XDG HOME path introduced in distro/"
fi

# 5. workflows parse as YAML (python yaml; skip if unavailable)
if python3 -c 'import yaml' 2>/dev/null; then
  for wf in .github/workflows/*.yml; do
    python3 -c "import yaml,sys; yaml.safe_load(open('$wf'))" || fail "invalid YAML: $wf"
  done
fi

# 6. policy files all consult cleanly
swipl -q -g "consult('.prolog/universe'), halt" -t "halt(1)" . 2>/dev/null \
  || swipl -q -g "consult('.prolog/universe'), halt" -t "halt(1)" || fail "control plane does not consult"

echo "STRUCTURE-OK"
