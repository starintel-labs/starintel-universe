#!/usr/bin/env bash
# Collect machine facts for the Prolog control plane.
# Writes facts/*.pl (gitignored). Never records secrets.
#
# Facts emitted:
#   pin(Component, Sha, Branch)      — current submodule pins
#   upstream_head(Component, Sha)    — remote default-branch heads
#   revision_note(universe, note(...)) — universe HEAD
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

FACTS_DIR="${STARINTEL_UNIVERSE_FACTS:-facts}"
mkdir -p "$FACTS_DIR"

# Map submodule directory name -> component atom
component_atom() {
  case "$1" in
    starintel-server) echo starintel_server ;;
    quasar)           echo quasar ;;
    quasar-ui)        echo quasar_ui ;;
    star-lang)        echo star_lang ;;
    star-kb)          echo star_kb ;;
    star-cl)          echo star_cl ;;
    prolog-rlm)       echo prolog_rlm ;;
    zara)             echo "zara vanta" ;;
    zara-plugins)     echo zara_plugins ;;
    dotfiles)         echo dotfiles ;;
    *)                return 1 ;;
  esac
}

: > "$FACTS_DIR/pins.pl"
: > "$FACTS_DIR/heads.pl"
: > "$FACTS_DIR/notes.pl"

git submodule status | while read -r _sha _path _rest; do
  sha="${_sha#+}"
  sha="${sha#-}"
  sha="${sha# }"
  name="$(basename "$_path")"
  # shellcheck disable=SC2312
  branch="$(git -C "$_path" branch --contains "$sha" 2>/dev/null | grep -E 'main|master' | head -1 | tr -d ' *' || true)"
  [ -z "$branch" ] && branch=detached
  for comp in $(component_atom "$name" 2>/dev/null || true); do
    printf "pin(%s, '%s', %s).\n" "$comp" "$sha" "$branch" >> "$FACTS_DIR/pins.pl"
  done
done

# upstream heads: best-effort (network); absent facts keep offline mode usable
for spec in \
  "starintel_server starintel-server master" \
  "quasar quasar main" \
  "quasar_ui quasar-ui main" \
  "star_lang star-lang main" \
  "star_kb star-kb main" \
  "star_cl star-cl master" \
  "prolog_rlm prolog-rlm main" \
  "zara zara master" \
  "vanta zara master" \
  "zara_plugins zara-plugins main" \
  "dotfiles dotfiles master"; do
  set -- $spec
  comp="$1"; repo="$2"; branch="$3"
  head="$(git ls-remote "https://git.starintel.actor/nsaspy/${repo}.git" "refs/heads/${branch}" 2>/dev/null | cut -f1 || true)"
  [ -n "$head" ] && printf "upstream_head(%s, '%s').\n" "$comp" "$head" >> "$FACTS_DIR/heads.pl"
done

printf "revision_note(universe, note(sha('%s'))).\n" "$(git rev-parse HEAD)" >> "$FACTS_DIR/notes.pl"

echo "facts written to $FACTS_DIR" >&2
