#!/usr/bin/env bash
# packaging/arch/stage.sh — assemble makepkg input from the collect_staging
# tree.
#
# Usage: packaging/arch/stage.sh [stage-dir]
#
# Produces <stage-dir>/vanta/ and <stage-dir>/starintel/ package subsets
# plus versioned PKGBUILD copies (pkgver substituted from release_version()).
# build-arch.sh mounts this directory at /input inside archlinux:base and
# runs makepkg against it in a clean per-package directory.
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../common.sh
source "$script_dir/../common.sh"

root="$(universe_root)"
version="$(release_version)"
stage_dir="${1:-$root/dist/.staging/arch}"
staging_root="$(dirname "$stage_dir")"

echo "== arch staging (version $version) =="
collect_staging "$staging_root/universe"

rm -rf "$stage_dir"
mkdir -p "$stage_dir"
for pkg in vanta starintel; do
  copy_package_subset "$staging_root/universe" "$pkg" "$stage_dir/$pkg/payload"
  # arch is usr-merged: /lib belongs to the filesystem package, so the
  # payload carries systemd units under usr/lib/systemd/system instead.
  if [ -d "$stage_dir/$pkg/payload/lib" ]; then
    mkdir -p "$stage_dir/$pkg/payload/usr"
    mv "$stage_dir/$pkg/payload/lib/systemd" "$stage_dir/$pkg/payload/usr/lib-systemd-tmp"
    rmdir "$stage_dir/$pkg/payload/lib"
    mkdir -p "$stage_dir/$pkg/payload/usr/lib"
    mv "$stage_dir/$pkg/payload/usr/lib-systemd-tmp" "$stage_dir/$pkg/payload/usr/lib/systemd"
  fi
  sed "s/__UNIVERSE_VERSION__/$version/" "$script_dir/PKGBUILD-$pkg" \
    > "$stage_dir/$pkg/PKGBUILD"
done

echo "arch stage complete: $stage_dir/{vanta,starintel}"
