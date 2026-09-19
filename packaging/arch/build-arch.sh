#!/usr/bin/env bash
# packaging/arch/build-arch.sh — build vanta and starintel arch packages.
#
# For each package: prepare a clean build directory with the staged tree
# (packaging/arch/stage.sh), then run makepkg inside docker
# $ARCH_DOCKER_IMAGE (default archlinux:base). The staged input is mounted
# read-only at /input; makepkg runs as an unprivileged build user so it
# cannot scribble on the host tree. Artifacts are copied to dist/.
#
# python is installed into the container when missing so makepkg's
# dependency check on `python` is real; pass ARCH_NODEPS=1 to skip.
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../common.sh
source "$script_dir/../common.sh"

root="$(universe_root)"
version="$(release_version)"
dist="$root/dist"
stage_dir="$dist/.staging/arch"
image="${ARCH_DOCKER_IMAGE:-archlinux:base}"

command -v docker >/dev/null 2>&1 || { echo "build-arch.sh: docker required" >&2; exit 1; }

bash "$script_dir/stage.sh" "$stage_dir"

nodeps_flag=""
[ "${ARCH_NODEPS:-0}" = "1" ] && nodeps_flag="--nodeps"

build_one() {
  local pkg="$1"
  local build_root="$stage_dir/build/$pkg"
  rm -rf "$build_root"
  mkdir -p "$build_root"
  cp "$stage_dir/$pkg/PKGBUILD" "$build_root/PKGBUILD"

  echo "== makepkg $pkg (in $image) =="
  docker run --rm -i \
    -v "$(cd "$stage_dir" && pwd):/input:ro" \
    -v "$(cd "$build_root" && pwd):/build" \
    "$image" bash -s <<EOF
set -euo pipefail
# makepkg refuses to run as root; use an unprivileged build user that owns
# the working copy.
useradd -m builduser 2>/dev/null || true
cp /input/$pkg/PKGBUILD /build/PKGBUILD
chown -R builduser:builduser /build
# runtime deps for makepkg itself (fakeroot) and the dependency check (python)
pacman -Sy --noconfirm --needed fakeroot python >/dev/null
$([ -n "$nodeps_flag" ] && echo 'deps="--nodeps"' || echo 'deps=""')
runuser -u builduser -- bash -c 'cd /build && makepkg -f --noconfirm --nosign' \$deps
EOF

  local artifact
  artifact="$(find "$build_root" -maxdepth 1 -name "$pkg-$version-*.pkg.tar.zst" | head -n1)"
  [ -n "$artifact" ] || { echo "build-arch.sh: no .pkg.tar.zst produced for $pkg" >&2; exit 1; }
  mv -f "$artifact" "$dist/"
}

mkdir -p "$dist"
build_one vanta
build_one starintel

vanta_pkg="$dist/vanta-$version-1-x86_64.pkg.tar.zst"
starintel_pkg="$dist/starintel-$version-1-x86_64.pkg.tar.zst"
write_manifest "$dist" arch "$vanta_pkg" "$starintel_pkg"

echo
echo "== arch build complete =="
ls -l "$vanta_pkg" "$starintel_pkg"
