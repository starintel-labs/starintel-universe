#!/usr/bin/env bash
# tests/packaging/install-test.sh — distro package install test driver.
#
# Usage: tests/packaging/install-test.sh (deb|rpm|arch)
#
# Runs the install/uninstall checks inside docker with the matching image:
#   deb -> ubuntu:24.04   rpm -> fedora:41   arch -> archlinux:base
#
# In-container checks (each prints PASS/FAIL, exit nonzero on any failure):
#   1. /opt binaries exist
#   2. desktop files validate (desktop-file-validate where available,
#      otherwise Exec=/opt/vanta/bin path check)
#   3. service units validate (systemd-analyze verify where available;
#      starintel-server.service additionally tolerates ONLY the documented
#      missing-binary diagnostic — the SBCL server binary is packaged
#      separately from nix; the unit ships inert and is never enabled)
#   4. /opt/vanta/bin/vanta --help exits 0 offline (wrapper degrades
#      gracefully when zara's optional heavy deps are absent)
#   5. python3 -c 'import zara' against the packaged source
#   6. /opt/starintel/bin/star-kb-validate --help exits 0 or 2
#   7. no service was enabled or started by the package install
#   8. XDG behaviour: vanta run with a clean HOME creates only XDG trees
#      (plus the in-XDG zarathushtra->vanta bridge), never $HOME dotdirs
#   9. clean uninstall leaves no /opt/vanta
set -euo pipefail

usage() { echo "usage: $0 (deb|rpm|arch)" >&2; exit 2; }
[ "$#" -eq 1 ] || usage
KIND="$1"
case "$KIND" in
  deb) IMAGE="${TEST_IMAGE_UBUNTU:-ubuntu:24.04}" ;;
  rpm) IMAGE="${TEST_IMAGE_FEDORA:-fedora:41}" ;;
  arch) IMAGE="${TEST_IMAGE_ARCH:-archlinux:base}" ;;
  *) usage ;;
esac

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
universe="$(cd "$script_dir/../.." && pwd)"
dist="$universe/dist"

command -v docker >/dev/null 2>&1 || { echo "install-test.sh: docker required" >&2; exit 1; }
[ -d "$dist" ] || { echo "install-test.sh: $dist missing — build packages first" >&2; exit 1; }

case "$KIND" in
  deb)  ls "$dist"/vanta_*_amd64.deb "$dist"/starintel_*_amd64.deb >/dev/null 2>&1 || { echo "install-test.sh: no debs in $dist" >&2; exit 1; } ;;
  rpm)  ls "$dist"/vanta-*.x86_64.rpm "$dist"/starintel-*.x86_64.rpm >/dev/null 2>&1 || { echo "install-test.sh: no rpms in $dist" >&2; exit 1; } ;;
  arch) ls "$dist"/vanta-*.pkg.tar.zst "$dist"/starintel-*.pkg.tar.zst >/dev/null 2>&1 || { echo "install-test.sh: no arch packages in $dist" >&2; exit 1; } ;;
esac

echo "== install-test ($KIND) in $IMAGE =="
docker run --rm -i -v "$(cd "$dist" && pwd):/pkg:ro" "$IMAGE" bash -s "$KIND" <<'CONTAINER'
set -u
KIND="$1"
PASS=0
FAIL=0

ok()  { PASS=$((PASS + 1)); echo "PASS: $*"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL: $*"; }

ensure_python3() {
  if command -v python3 >/dev/null 2>&1; then return 0; fi
  echo "install-test: python3 missing — installing it first"
  case "$KIND" in
    deb)  apt-get update -qq && DEBIAN_FRONTEND=noninteractive apt-get install -y -qq python3 ;;
    rpm)  dnf install -y -q python3 ;;
    arch) pacman -Sy --noconfirm --needed python ;;
  esac
}

install_packages() {
  case "$KIND" in
    deb)  dpkg -i /pkg/vanta_*_amd64.deb /pkg/starintel_*_amd64.deb ;;
    rpm)  dnf install -y /pkg/vanta-*.x86_64.rpm /pkg/starintel-*.x86_64.rpm ;;
    arch) pacman -U --noconfirm /pkg/vanta-*.pkg.tar.zst /pkg/starintel-*.pkg.tar.zst ;;
  esac
}

remove_packages() {
  case "$KIND" in
    deb)  dpkg -r vanta starintel ;;
    rpm)  dnf remove -y vanta starintel ;;
    arch) pacman -R --noconfirm vanta starintel ;;
  esac
}

ensure_python3

# --- 1. install + binaries ------------------------------------------------
if install_packages >/tmp/install.log 2>&1; then
  ok "$KIND packages installed"
else
  bad "$KIND package install failed"; sed -n '1,25p' /tmp/install.log
fi

for bin in vanta vanta-server vanta-desktop vanta-wake vanta-dictate; do
  [ -x "/opt/vanta/bin/$bin" ] && ok "binary /opt/vanta/bin/$bin" || bad "missing /opt/vanta/bin/$bin"
done
for bin in star-kb-validate star-kb-validate-docs star-kb-sync collect-facts.sh; do
  [ -e "/opt/starintel/bin/$bin" ] && ok "binary /opt/starintel/bin/$bin" || bad "missing /opt/starintel/bin/$bin"
done

# --- 2. desktop files -------------------------------------------------------
for df in /usr/share/applications/vanta-desktop.desktop /usr/share/applications/vanta-console.desktop; do
  [ -f "$df" ] || { bad "desktop file $df missing"; continue; }
  if grep -q '^Exec=/nix/store' "$df"; then
    bad "$df Exec points into /nix/store"
  elif ! grep -q '^Exec=/opt/vanta/bin/' "$df"; then
    bad "$df Exec is not under /opt/vanta/bin"
  elif command -v desktop-file-validate >/dev/null 2>&1; then
    if desktop-file-validate "$df" 2>/tmp/dfv.log; then ok "desktop-file-validate $df"; else bad "desktop-file-validate $df"; sed -n '1,5p' /tmp/dfv.log; fi
  else
    ok "$df Exec path (desktop-file-validate unavailable — skipped strict validate)"
  fi
done
[ -f /usr/share/icons/hicolor/scalable/apps/vanta.svg ] && ok "vanta.svg icon installed" || bad "vanta.svg icon missing"

# --- 3. unit validation -----------------------------------------------------
if command -v systemd-analyze >/dev/null 2>&1; then
  for unit in vanta-server.service vanta-wake.service; do
    out="$(systemd-analyze verify "/lib/systemd/system/$unit" 2>&1)"; rc=$?
    if [ $rc -eq 0 ]; then ok "systemd-analyze verify $unit"
    else bad "systemd-analyze verify $unit"; printf '%s\n' "$out" | sed -n '1,10p'; fi
  done
  # starintel-server.service: the SBCL server binary is NOT in this package
  # (it is built via nix); the unit ships inert. Only the exact documented
  # missing-ExecStart diagnostic is tolerated.
  out="$(systemd-analyze verify /lib/systemd/system/starintel-server.service 2>&1)"
  unexpected="$(printf '%s\n' "$out" | grep -v '^$' | grep -v 'Command /opt/starintel/bin/starintel-server is not executable' || true)"
  if [ -z "$unexpected" ]; then
    ok "systemd-analyze verify starintel-server.service (only the documented missing-binary note)"
  else
    bad "starintel-server.service verify reported unexpected problems"
    printf '%s\n' "$unexpected" | sed -n '1,10p'
  fi
else
  ok "systemd-analyze unavailable — unit verify skipped"
fi

# --- 4. vanta --help offline ------------------------------------------------
if HOME=/tmp/vanta-help-home PYTHONDONTWRITEBYTECODE=1 /opt/vanta/bin/vanta --help >/tmp/vanta-help.log 2>&1; then
  ok "vanta --help exits 0 (offline)"
else
  bad "vanta --help failed"; sed -n '1,10p' /tmp/vanta-help.log
fi

# --- 5. import zara from packaged source ------------------------------------
if PYTHONDONTWRITEBYTECODE=1 PYTHONPATH=/opt/vanta/lib/python python3 -c 'import zara; print(zara.__file__)' >/tmp/zara-import.log 2>&1; then
  ok "python3 import zara (packaged source)"
else
  bad "python3 import zara failed"; sed -n '1,10p' /tmp/zara-import.log
fi

# --- 6. star-kb tooling -------------------------------------------------------
# validate-docs.py needs a roam tree with ledgers under project_root(); outside
# git it uses cwd, so run it from a minimal valid scratch roam tree.
STARKB=/tmp/starkb-check
rm -rf "$STARKB"; mkdir -p "$STARKB/roam/research" "$STARKB/roam/design" \
  "$STARKB/roam/implement" "$STARKB/roam/indexes"
touch "$STARKB/roam/.implemented" "$STARKB/roam/.rejected"
star_kb_out=0
(cd "$STARKB" && PYTHONDONTWRITEBYTECODE=1 /opt/starintel/bin/star-kb-validate --help) >/tmp/starkb.log 2>&1 || star_kb_out=$?
if [ "$star_kb_out" -eq 0 ] || [ "$star_kb_out" -eq 2 ]; then
  ok "star-kb-validate --help exits $star_kb_out"
else
  bad "star-kb-validate --help exited $star_kb_out"; sed -n '1,10p' /tmp/starkb.log
fi

# --- 7. nothing auto-enabled/started -----------------------------------------
for unit in vanta-server.service vanta-wake.service starintel-server.service; do
  if [ -e "/etc/systemd/system/multi-user.target.wants/$unit" ]; then
    bad "$unit was auto-enabled by package install"
  else
    ok "$unit not auto-enabled"
  fi
done

# --- 8. XDG behaviour ----------------------------------------------------------
XDGHOME=/tmp/vanta-xdg-home
rm -rf "$XDGHOME"; mkdir -p "$XDGHOME"
HOME="$XDGHOME" PYTHONDONTWRITEBYTECODE=1 /opt/vanta/bin/vanta --help >/dev/null 2>&1 || true
[ -d "$XDGHOME/.config/vanta" ] && ok "XDG config dir created (\$XDG_CONFIG_HOME/vanta)" || bad "no \$HOME/.config/vanta"
[ -f "$XDGHOME/.config/vanta/config.toml" ] && ok "default config.toml seeded into XDG config" || bad "config.toml not seeded"
if [ -L "$XDGHOME/.config/zarathushtra" ] && [ "$(readlink "$XDGHOME/.config/zarathushtra")" = "vanta" ]; then
  ok "zarathushtra->vanta bridge symlink inside XDG config"
else
  bad "missing zarathushtra->vanta bridge in XDG config"
fi
for dotdir in .zara .vanta .zarathushtra; do
  if [ -e "$XDGHOME/$dotdir" ]; then bad "legacy \$HOME/$dotdir dotdir was created"; else ok "no legacy \$HOME/$dotdir dotdir"; fi
done

# --- 9. clean uninstall ---------------------------------------------------------
if remove_packages >/tmp/remove.log 2>&1; then
  ok "$KIND packages removed"
else
  bad "$KIND package removal failed"; sed -n '1,15p' /tmp/remove.log
fi
[ ! -e /opt/vanta ] && ok "no /opt/vanta left after uninstall" || bad "/opt/vanta left after uninstall"
[ ! -e /opt/starintel ] && ok "no /opt/starintel left after uninstall" || bad "/opt/starintel left after uninstall"

echo
echo "== install-test ($KIND): $PASS passed, $FAIL failed =="
[ "$FAIL" -eq 0 ] || exit 1
exit 0
CONTAINER
rc=$?
echo "== install-test ($KIND) container exit: $rc =="
exit $rc
