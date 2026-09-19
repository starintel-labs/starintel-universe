#!/usr/bin/env bash
# VANTA distribution behavior: offline, XDG-only, no provider required.
# Runs against the nix-built package (builds it if needed).
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

OUT="${VANTA_OUT:-/tmp/opencode/vanta-build}"
if [ ! -x "$OUT/bin/vanta" ]; then
  nix build .#vanta --out-link "$OUT"
fi

FAIL=0
H=$(mktemp -d)
export HOME=$H
export XDG_CONFIG_HOME=$H/.config XDG_DATA_HOME=$H/.local/share \
       XDG_STATE_HOME=$H/.local/state XDG_CACHE_HOME=$H/.cache

# 1. offline help: no provider, no network
timeout 60 "$OUT/bin/vanta" --help >/dev/null 2>&1 || FAIL=1
echo "vanta --help rc=$? (must be 0)"

# 2. canonical XDG locations exist
for d in "$XDG_CONFIG_HOME/vanta" "$XDG_DATA_HOME/vanta" \
         "$XDG_STATE_HOME/vanta" "$XDG_CACHE_HOME/vanta"; do
  [ -d "$d" ] || { echo "missing $d"; FAIL=1; }
done

# 3. compatibility bridge lives INSIDE the XDG tree
[ -L "$XDG_CONFIG_HOME/zarathushtra" ] || { echo "no bridge symlink"; FAIL=1; }

# 4. no new dot-dirs in HOME
BAD=$(ls -a "$H" | grep -E '^\.[a-zA-Z0-9]' | grep -vE '^\.$|^\.\.$|^\.config$|^\.local$|^\.cache$' || true)
[ -z "$BAD" ] || { echo "unexpected HOME entries: $BAD"; FAIL=1; }

# 5. default config deployed and offline-first
grep -q 'provider = "ollama"' "$XDG_CONFIG_HOME/vanta/config.toml" || FAIL=1
grep -q '^enabled = false' "$XDG_CONFIG_HOME/vanta/config.toml" || FAIL=1

# 6. desktop entries validate (where desktop-file-validate exists)
if command -v desktop-file-validate >/dev/null; then
  desktop-file-validate "$OUT"/share/applications/*.desktop || FAIL=1
fi

[ $FAIL -eq 0 ] && echo VANTA-OK || exit 1
