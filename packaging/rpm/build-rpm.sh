#!/usr/bin/env bash
# packaging/rpm/build-rpm.sh — build vanta and starintel RPMs.
#
# Produces dist/vanta-<version>-1.x86_64.rpm and
# dist/starintel-<version>-1.x86_64.rpm.
#
# Always generates an rpmbuild-compatible tree (SPECS/ + BUILDROOT/) under
# dist/.staging/rpm. When rpmbuild exists it is used
#   rpmbuild -bb --define '_topdir ...'
# otherwise the script fails with instructions. Set RPM_DOCKER=1 to run the
# rpmbuild step inside $RPM_DOCKER_IMAGE (default fedora:41) which installs
# rpm-build from the distro repos.
#
# %post runs `systemctl daemon-reload` only — never enable/start.
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../common.sh
source "$script_dir/../common.sh"

root="$(universe_root)"
version="$(release_version)"
export SOURCE_DATE_EPOCH="${SOURCE_DATE_EPOCH:-$(source_date_epoch)}"
dist="$root/dist"
staging_root="$dist/.staging"
topdir="$staging_root/rpm"

echo "== starintel-universe rpm build =="
echo "   version : $version"

mkdir -p "$dist"
collect_staging "$staging_root/universe"

make_buildroot() {
  local pkg="$1" buildroot="$2"
  rm -rf "$buildroot"
  copy_package_subset "$staging_root/universe" "$pkg" "$buildroot"
}

write_vanta_spec() {
  local spec="$1"
  cat > "$spec" <<EOF
Name: vanta
Version: $version
Release: 1
Summary: VANTA - the StarIntel agent distribution (wraps upstream Zara)
License: GPL-3.0-only AND MIT
URL: https://git.starintel.actor/starintel/starintel-universe
Packager: StarIntel <nsaspy@fedora.email>
Requires: python3
Source0: %{name}-payload.tar

%description
VANTA is the StarIntel distribution identity of Zara: a voice/desktop agent
packaged from the pinned components/zara python source so it runs on any
python3, fully offline-first (default provider is local ollama).

Ships vanta, vanta-server, vanta-desktop, vanta-wake and vanta-dictate
wrappers under /opt/vanta/bin, XDG-only state (no \$HOME dotdirs), and
opt-in systemd units (never auto-enabled). Heavy optional dependencies
(numpy, httpx, soundfile, ...) are intentionally not packaged; see
/usr/share/doc/vanta/README.XDG.md.

%prep
:

%build
:

%install
rm -rf %{buildroot}
mkdir -p %{buildroot}
tar -xf %{SOURCE0} -C %{buildroot}

%post
if command -v systemctl >/dev/null 2>&1; then
  systemctl daemon-reload || :
fi

%preun
if [ "\$1" = "0" ] && command -v systemctl >/dev/null 2>&1; then
  # removal (not upgrade): bounce daemons only if they are running
  systemctl try-restart vanta-server.service vanta-wake.service >/dev/null 2>&1 || :
fi

%files
%defattr(-,root,root,-)
/opt/vanta
/usr/share/applications/vanta-desktop.desktop
/usr/share/applications/vanta-console.desktop
/usr/share/icons/hicolor/scalable/apps/vanta.svg
%dir /usr/share/doc/vanta
/usr/share/doc/vanta/copyright
/usr/share/doc/vanta/README.XDG.md
/lib/systemd/system/vanta-server.service
/lib/systemd/system/vanta-wake.service
EOF
}

write_starintel_spec() {
  local spec="$1"
  cat > "$spec" <<EOF
Name: starintel
Version: $version
Release: 1
Summary: StarIntel Universe tooling (star-kb control plane)
License: MIT
URL: https://git.starintel.actor/starintel/starintel-universe
Packager: StarIntel <nsaspy@fedora.email>
Requires: python3
Source0: %{name}-payload.tar

%description
The starintel distro package ships the pinned components/star-kb research
control-plane tooling (star-kb-validate, star-kb-sync, ...) and the
universe scripts under /opt/starintel/bin, plus an inert (never enabled)
hardened starintel-server.service unit.

%prep
:

%build
:

%install
rm -rf %{buildroot}
mkdir -p %{buildroot}
tar -xf %{SOURCE0} -C %{buildroot}

%post
if command -v systemctl >/dev/null 2>&1; then
  systemctl daemon-reload || :
fi

%files
%defattr(-,root,root,-)
/opt/starintel
/lib/systemd/system/starintel-server.service
%dir /usr/share/doc/starintel
/usr/share/doc/starintel/copyright
EOF
}

assemble() {
  mkdir -p "$topdir/SPECS" "$topdir/SOURCES" "$topdir/BUILD" "$topdir/RPMS" "$topdir/SRPMS" "$topdir/BUILDROOT"
  for pkg in vanta starintel; do
    local buildroot="$topdir/BUILDROOT/$pkg-$version-1.x86_64"
    make_buildroot "$pkg" "$buildroot"
    # deterministic payload tarball consumed by %install via %{SOURCE0}
    tar --sort=name --mtime="@${SOURCE_DATE_EPOCH:-0}" \
      --owner=0 --group=0 --numeric-owner \
      -cf "$topdir/SOURCES/$pkg-payload.tar" -C "$buildroot" .
    if [ "$pkg" = "vanta" ]; then
      write_vanta_spec "$topdir/SPECS/$pkg.spec"
    else
      write_starintel_spec "$topdir/SPECS/$pkg.spec"
    fi
  done
  echo "build-rpm.sh: assembled rpmbuild tree at $topdir" >&2
}

run_rpmbuild_host() {
  for pkg in vanta starintel; do
    rpmbuild -bb --define "_topdir $topdir" "$topdir/SPECS/$pkg.spec"
  done
}

run_rpmbuild_docker() {
  local image="${RPM_DOCKER_IMAGE:-fedora:41}"
  local abstop abstage
  abstop="$(cd "$topdir" && pwd)"
  abstage="$(cd "$staging_root" && pwd)"
  docker run --rm -i \
    -v "$abstop:/topdir" -v "$abstage/universe:/universe:ro" -v "$(cd "$dist" && pwd):/dist" \
    -e PKG_VERSION="$version" \
    "$image" bash -s <<'EOF'
set -euo pipefail
command -v rpmbuild >/dev/null 2>&1 || dnf install -y rpm-build
for pkg in vanta starintel; do
  rpmbuild -bb \
    --define '_topdir /topdir' \
    --define "buildroot /topdir/BUILDROOT/$pkg-${PKG_VERSION}-1.x86_64" \
    "/topdir/SPECS/$pkg.spec"
done
for f in /topdir/RPMS/*/*.rpm; do
  cp -f "$f" "/dist/$(basename "$f")"
  rm -f "$f"
done
EOF
}

collect_rpms() {
  local found
  for f in "$topdir"/RPMS/*/*.rpm; do
    [ -e "$f" ] || continue
    mv -f "$f" "$dist/"
    found=1
  done
  [ -n "${found:-}" ] || return 1
}

assemble

if command -v rpmbuild >/dev/null 2>&1; then
  run_rpmbuild_host
  collect_rpms
elif [ "${RPM_DOCKER:-0}" = "1" ]; then
  command -v docker >/dev/null 2>&1 || { echo "build-rpm.sh: RPM_DOCKER=1 but no docker" >&2; exit 1; }
  run_rpmbuild_docker
else
  cat >&2 <<EOF
build-rpm.sh: rpmbuild not found on this host and RPM_DOCKER is not set.

Options:
  1. install rpm-build and re-run:
       packaging/rpm/build-rpm.sh
  2. run the rpmbuild step inside the $RPM_DOCKER_IMAGE container:
       RPM_DOCKER=1 packaging/rpm/build-rpm.sh
     (this installs rpm-build from the fedora repositories)
The rpmbuild-compatible tree is already assembled at:
  $topdir
EOF
  exit 1
fi

vanta_rpm="$dist/vanta-$version-1.x86_64.rpm"
starintel_rpm="$dist/starintel-$version-1.x86_64.rpm"
[ -f "$vanta_rpm" ] || { echo "build-rpm.sh: expected $vanta_rpm missing (check RPMS arch naming)" >&2; ls "$topdir/RPMS"/* >&2 || true; exit 1; }
[ -f "$starintel_rpm" ] || { echo "build-rpm.sh: expected $starintel_rpm missing" >&2; exit 1; }

write_manifest "$dist" rpm "$vanta_rpm" "$starintel_rpm"

echo
echo "== rpm build complete =="
ls -l "$vanta_rpm" "$starintel_rpm"
