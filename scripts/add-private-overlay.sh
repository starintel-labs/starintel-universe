#!/usr/bin/env bash
# Add PRIVATE StarIntel components as an overlay for local development.
# Private submodules are intentionally NOT part of the public checkout:
# anonymous clone --recursive must always succeed, and private content
# must never leak into public release artifacts.
#
# Usage: scripts/add-private-overlay.sh
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

add() {
  local url="$1" path="$2"
  [ -d "$path" ] && { echo "exists: $path"; return; }
  git submodule add "$url" "$path"
}

add ssh://forgejo@git.starintel.actor/starintel-labs/starintel-pro-actors.git \
    components/private/starintel-pro-actors

echo "private overlay added. These paths are excluded from packaging"
echo "(packaging/common.sh refuses components/private) and MUST NOT be"
echo "referenced by public workflows."
