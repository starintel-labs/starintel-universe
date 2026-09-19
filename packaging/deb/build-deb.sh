#!/usr/bin/env bash
# packaging/deb/build-deb.sh — build vanta and starintel debs from staging.
#
# Produces dist/vanta_<version>_amd64.deb and dist/starintel_<version>_amd64.deb
# via dpkg-deb --build (no pbuilder needed for artifacts). Uses the host
# dpkg-deb when present, otherwise falls back to $DEB_DOCKER_IMAGE
# (default debian:bookworm-slim — already the standard builder image).
#
# No package script enables or starts any service (privacy: no autostart).
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../common.sh
source "$script_dir/../common.sh"

root="$(universe_root)"
version="$(release_version)"
export SOURCE_DATE_EPOCH="${SOURCE_DATE_EPOCH:-$(source_date_epoch)}"
dist="$root/dist"
staging_root="$dist/.staging"

echo "== starintel-universe deb build =="
echo "   version : $version"
echo "   epoch   : $SOURCE_DATE_EPOCH"

mkdir -p "$dist"
collect_staging "$staging_root/universe"

make_deb_tree() {
  local pkg="$1" tree="$2"
  rm -rf "$tree"
  copy_package_subset "$staging_root/universe" "$pkg" "$tree"
  mkdir -p "$tree/DEBIAN"
  chmod 0755 "$tree/DEBIAN"
}

write_vanta_debian() {
  local tree="$1"
  cat > "$tree/DEBIAN/control" <<EOF
Package: vanta
Version: $version
Architecture: amd64
Maintainer: StarIntel <nsaspy@fedora.email>
Installed-Size: $(du -sk "$tree/opt" "$tree/usr" 2>/dev/null | awk '{s+=$1} END {print s+0}')
Depends: python3
Section: x11
Priority: optional
Homepage: https://git.starintel.actor/starintel/starintel-universe
Description: VANTA - the StarIntel agent distribution (wraps upstream Zara)
 VANTA is the StarIntel distribution identity of Zara: a voice/desktop
 agent packaged from the pinned components/zara python source so it runs
 on any python3, fully offline-first (default provider is local ollama).
 .
 Ships vanta, vanta-server, vanta-desktop, vanta-wake and vanta-dictate
 wrappers under /opt/vanta/bin, XDG-only state (no \$HOME dotdirs), and
 opt-in systemd units (never auto-enabled). Heavy optional dependencies
 (numpy, httpx, soundfile, ...) are intentionally not packaged; see
 /usr/share/doc/vanta/README.XDG.md.
EOF

  cat > "$tree/DEBIAN/postinst" <<'EOF'
#!/bin/sh
# vanta postinst — refresh caches only. Never enable or start a service.
set -e
if command -v systemctl >/dev/null 2>&1; then
  systemctl daemon-reload || true
fi
if command -v update-desktop-database >/dev/null 2>&1; then
  update-desktop-database || true
fi
exit 0
EOF

  cat > "$tree/DEBIAN/prerm" <<'EOF'
#!/bin/sh
# vanta prerm — before an upgrade, bounce the daemons if they are running
# (guarded; try-restart only restarts units that are active). Nothing is
# stopped or disabled on plain remove beyond what dpkg already does.
set -e
if [ "${1:-}" = "upgrade" ] && command -v systemctl >/dev/null 2>&1; then
  systemctl try-restart vanta-server.service vanta-wake.service >/dev/null 2>&1 || true
fi
exit 0
EOF
  chmod 0755 "$tree/DEBIAN/postinst" "$tree/DEBIAN/prerm"
}

write_starintel_debian() {
  local tree="$1"
  cat > "$tree/DEBIAN/control" <<EOF
Package: starintel
Version: $version
Architecture: amd64
Maintainer: StarIntel <nsaspy@fedora.email>
Installed-Size: $(du -sk "$tree/opt" "$tree/usr" 2>/dev/null | awk '{s+=$1} END {print s+0}')
Depends: python3
Section: utils
Priority: optional
Homepage: https://git.starintel.actor/starintel/starintel-universe
Description: StarIntel Universe tooling (star-kb control plane)
 The starintel distro package ships the pinned components/star-kb research
 control-plane tooling (star-kb-validate, star-kb-sync, ...) and the
 universe scripts under /opt/starintel/bin, plus an inert (never enabled)
 hardened starintel-server.service unit.
EOF

  cat > "$tree/DEBIAN/postinst" <<'EOF'
#!/bin/sh
# starintel postinst — refresh systemd only. Never enable or start a service.
set -e
if command -v systemctl >/dev/null 2>&1; then
  systemctl daemon-reload || true
fi
exit 0
EOF

  cat > "$tree/DEBIAN/prerm" <<'EOF'
#!/bin/sh
# starintel prerm — nothing to do; the unit is never enabled by this package.
set -e
exit 0
EOF
  chmod 0755 "$tree/DEBIAN/postinst" "$tree/DEBIAN/prerm"
}

build_tree() {
  local tree="$1" out="$2"
  clamp_mtimes "$tree"
  if command -v dpkg-deb >/dev/null 2>&1; then
    dpkg-deb --root-owner-group --uniform-compression -Zgzip \
      --build "$tree" "$out"
  else
    local image="${DEB_DOCKER_IMAGE:-debian:bookworm-slim}"
    command -v docker >/dev/null 2>&1 || {
      echo "build-deb.sh: no host dpkg-deb and no docker — cannot build debs." >&2
      exit 1
    }
    local absdist; absdist="$(cd "$dist" && pwd)"
    docker run --rm -u "$(id -u):$(id -g)" -e SOURCE_DATE_EPOCH \
      -v "$absdist:/work" -w /work \
      "$image" dpkg-deb --root-owner-group --uniform-compression -Zgzip \
        --build "/work/.staging/$(basename "$tree")" "/work/$(basename "$out")"
  fi
}

make_deb_tree vanta "$staging_root/vanta"
write_vanta_debian "$staging_root/vanta"
make_deb_tree starintel "$staging_root/starintel"
write_starintel_debian "$staging_root/starintel"

vanta_deb="$dist/vanta_${version}_amd64.deb"
starintel_deb="$dist/starintel_${version}_amd64.deb"
rm -f "$vanta_deb" "$starintel_deb"

build_tree "$staging_root/vanta" "$vanta_deb"
build_tree "$staging_root/starintel" "$starintel_deb"

# verify with host tooling when available
if command -v dpkg-deb >/dev/null 2>&1; then
  dpkg-deb --info "$vanta_deb" >/dev/null
  dpkg-deb --info "$starintel_deb" >/dev/null
fi

write_manifest "$dist" deb "$vanta_deb" "$starintel_deb"

echo
echo "== deb build complete =="
ls -l "$vanta_deb" "$starintel_deb"
