#!/usr/bin/env bash
# packaging/common.sh — shared staging logic for the StarIntel Universe
# distro packages (deb / rpm / arch).
#
# Sourced by packaging/{deb,rpm,arch}/* builders and tests. Provides:
#   universe_root           — absolute path to the starintel-universe checkout
#   release_version         — <major.minor> from manifest.json (fallback 0.YYYYMMDD)
#   source_date_epoch       — deterministic build timestamp (HEAD commit time)
#   collect_staging <dir>   — assemble the full staging tree (opt/, lib/, usr/)
#   copy_package_subset     — copy per-package file sets out of the staging tree
#   write_manifest <dist>   — JSON manifest of components + artifact sha256s
#
# VANTA payload model (see packaging/README.org):
#   The nix-built vanta closure cannot run outside nix (its bin/ shims exec
#   /nix/store interpreters), so distro packages carry the *pinned zara
#   Python source* (pip-installed from components/zara with --no-index
#   --no-deps --no-build-isolation) plus generated vanta* wrappers that exec
#   the system python3. Desktop files, icon and default config come from
#   distro/vanta (or the nix share/ tree when /tmp/opencode/vanta-build
#   exists). The nix bin/ shims are deliberately NOT shipped.

set -euo pipefail

packaging_common_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ---------------------------------------------------------------------------
# universe_root — resolve the starintel-universe checkout.
# STARINTEL_UNIVERSE_ROOT wins; otherwise derive from this file's location.
universe_root() {
  if [ -n "${STARINTEL_UNIVERSE_ROOT:-}" ]; then
    printf '%s\n' "$STARINTEL_UNIVERSE_ROOT"
    return 0
  fi
  printf '%s\n' "$(cd "$packaging_common_dir/.." && pwd)"
}

# ---------------------------------------------------------------------------
# release_version — <major.minor>.
# Reads manifest.json at the universe root when present (keys tried in
# order: version, release_version, schema_version); falls back to
# 0.$(date +%Y%m%d) (already <major.minor>).
release_version() {
  local root manifest raw
  root="$(universe_root)"
  manifest="$root/manifest.json"
  if [ -f "$manifest" ]; then
    raw="$(python3 - "$manifest" <<'PY'
import json, sys
try:
    with open(sys.argv[1], encoding="utf-8") as fh:
        data = json.load(fh)
except Exception:
    sys.exit(1)
for key in ("version", "release_version", "schema_version"):
    value = data.get(key) if isinstance(data, dict) else None
    if isinstance(value, str) and value.strip():
        print(value.strip())
        sys.exit(0)
sys.exit(1)
PY
)" || raw=""
    if [ -n "$raw" ]; then
      printf '%s.%s\n' "${raw%%.*}" "$(printf '%s' "$raw" | cut -d. -f2)"
      return 0
    fi
  fi
  printf '0.%s\n' "$(date +%Y%m%d)"
}

# ---------------------------------------------------------------------------
# source_date_epoch — HEAD commit time (deterministic mtimes / compression).
source_date_epoch() {
  local root epoch
  root="$(universe_root)"
  epoch="$(git -C "$root" log -1 --format=%ct 2>/dev/null || true)"
  printf '%s\n' "${epoch:-0}"
}

clamp_mtimes() {
  # clamp_mtimes <dir> — set every mtime to SOURCE_DATE_EPOCH for reproducible
  # archives. Safe no-op when touch -h is unsupported.
  local dir="$1" epoch="${SOURCE_DATE_EPOCH:-$(source_date_epoch)}"
  [ -n "$epoch" ] && [ "$epoch" != "0" ] || return 0
  find "$dir" -exec touch -h -d "@$epoch" {} + 2>/dev/null || true
}

# ---------------------------------------------------------------------------
# Package file sets — the per-package subsets of the staging tree, shared by
# the deb, rpm and arch builders so all three distro payloads stay identical.
vanta_package_paths() {
  cat <<'EOF'
opt/vanta
usr/share/applications/vanta-desktop.desktop
usr/share/applications/vanta-console.desktop
usr/share/icons/hicolor/scalable/apps/vanta.svg
usr/share/doc/vanta
lib/systemd/system/vanta-server.service
lib/systemd/system/vanta-wake.service
EOF
}

starintel_package_paths() {
  cat <<'EOF'
opt/starintel
lib/systemd/system/starintel-server.service
usr/share/doc/starintel
EOF
}

# copy_package_subset <staging> <vanta|starintel> <dest>
copy_package_subset() {
  local staging="$1" pkg="$2" dest="$3" rel parent
  [ -d "$staging" ] || { echo "common.sh: staging tree missing: $staging" >&2; return 1; }
  mkdir -p "$dest"
  case "$pkg" in
    vanta) vanta_package_paths ;;
    starintel) starintel_package_paths ;;
    *) echo "common.sh: unknown package '$pkg'" >&2; return 1 ;;
  esac | while IFS= read -r rel; do
    if [ -e "$staging/$rel" ]; then
      parent="$(dirname "$dest/$rel")"
      mkdir -p "$parent"
      cp -a "$staging/$rel" "$parent/"
    else
      echo "common.sh: staging path missing: $staging/$rel" >&2
      exit 1
    fi
  done
}

# ---------------------------------------------------------------------------
# zara python staging — pip-install the pinned submodule into <dest>.
# Uses the host python3 when it has pip+setuptools, otherwise falls back to
# the docker image $VANTA_PYTHON_IMAGE (default python:3.11-slim, which
# bundles pip+setuptools; the produced layout is pure-python and runs on
# python3 >= 3.11 including ubuntu 24.04's 3.12).
stage_zara_python() {
  local dest="$1"
  local root; root="$(universe_root)"
  local src="$root/components/zara"
  [ -d "$src/zara" ] || {
    echo "common.sh: components/zara python package missing — cannot stage vanta." >&2
    echo "common.sh: (a lib/vanta placeholder tree is not acceptable; initialize" >&2
    echo "common.sh:  submodules and build vanta first: git submodule update --init)" >&2
    return 1
  }
  mkdir -p "$dest"
  if python3 -c 'import pip, setuptools' >/dev/null 2>&1; then
    local tmpsrc; tmpsrc="$(mktemp -d)"
    cp -a "$src/." "$tmpsrc/"
    SOURCE_DATE_EPOCH="${SOURCE_DATE_EPOCH:-$(source_date_epoch)}" \
      python3 -m pip install --quiet --no-index --no-deps --no-build-isolation \
        --target "$dest" "$tmpsrc" >&2
    rm -rf "$tmpsrc"
  else
    local image="${VANTA_PYTHON_IMAGE:-python:3.11-slim}"
    command -v docker >/dev/null 2>&1 || {
      echo "common.sh: host python3 lacks pip/setuptools and docker is unavailable;" >&2
      echo "common.sh: cannot pip-install zara from the local submodule." >&2
      return 1
    }
    local absdest; absdest="$(cd "$dest" && pwd)"
    docker run --rm \
      -u "$(id -u):$(id -g)" \
      -e HOME=/tmp \
      -e PIP_NO_CACHE_DIR=1 -e PIP_DISABLE_PIP_VERSION_CHECK=1 \
      -e SOURCE_DATE_EPOCH="${SOURCE_DATE_EPOCH:-$(source_date_epoch)}" \
      -v "$src:/src:ro" -v "$absdest:/out" \
      "$image" bash -ec '
        cp -r /src /tmp/zara-src
        python3 -m pip install --quiet --no-index --no-deps --no-build-isolation \
          --target /out /tmp/zara-src
        rm -rf /tmp/zara-src
      ' >&2
  fi
}

# ---------------------------------------------------------------------------
# vanta wrappers — mirror distro/vanta/package.nix shim semantics:
# XDG bootstrap + zarathushtra->vanta bridge + exec system python3 on the
# packaged zara source. Falls back to a usage notice when zara's optional
# heavy dependencies (numpy, httpx, soundfile, ...) are not installed, so
# `vanta --help` still exits 0 on a stock python3.
write_vanta_wrapper() {
  local name="$1" module="$2" run="$3" bin="$1"
  local out="$4/bin/$bin"
  mkdir -p "$4/bin"
  cat > "$out" <<WRAPPER
#!/usr/bin/env bash
# $name — VANTA ($name) shim, generated by starintel-universe packaging.
# Upstream: zara (pinned submodule components/zara), entrypoint: $run
set -u
VANTA_PREFIX=/opt/vanta
export VANTA_NO_PROVIDER="\${VANTA_NO_PROVIDER:-1}"
export PYTHONPATH="\$VANTA_PREFIX/lib/python\${PYTHONPATH:+:\$PYTHONPATH}"

# XDG bootstrap (no legacy \$HOME dotdirs are ever created).
: "\${HOME:=/tmp}"
export XDG_CONFIG_HOME="\${XDG_CONFIG_HOME:-\$HOME/.config}"
export XDG_DATA_HOME="\${XDG_DATA_HOME:-\$HOME/.local/share}"
export XDG_STATE_HOME="\${XDG_STATE_HOME:-\$HOME/.local/state}"
export XDG_CACHE_HOME="\${XDG_CACHE_HOME:-\$HOME/.cache}"
mkdir -p "\$XDG_CONFIG_HOME/vanta" "\$XDG_DATA_HOME/vanta" \\
  "\$XDG_STATE_HOME/vanta" "\$XDG_CACHE_HOME/vanta" 2>/dev/null || true
if [ ! -e "\$XDG_CONFIG_HOME/vanta/config.toml" ] && \\
    [ -e "\$VANTA_PREFIX/share/vanta/defaults/config.toml" ]; then
  install -m 0644 "\$VANTA_PREFIX/share/vanta/defaults/config.toml" \\
    "\$XDG_CONFIG_HOME/vanta/config.toml" 2>/dev/null || true
fi
# zarathushtra -> vanta compatibility bridge (symlinks INSIDE XDG trees only).
for _xdg in "\$XDG_CONFIG_HOME" "\$XDG_DATA_HOME" "\$XDG_STATE_HOME" "\$XDG_CACHE_HOME"; do
  if [ -d "\$_xdg" ] && [ ! -e "\$_xdg/zarathushtra" ]; then
    ln -sfn vanta "\$_xdg/zarathushtra" 2>/dev/null || true
  fi
done

if python3 -c 'import importlib; importlib.import_module("$module")' >/dev/null 2>&1; then
  exec python3 $run "\$@"
fi

# Optional heavy deps missing — degrade instead of traceback.
cat >&2 <<'NOTICE'
$name: zara's optional Python dependencies are not installed in this interpreter.
$name: install them with: python3 -m pip install -r \$VANTA_PREFIX/share/vanta/requirements.txt
NOTICE
case " \$* " in
  *" --help "*|*" -h "*|"  ")
    cat <<'USAGE'
$name — VANTA, the StarIntel agent distribution

usage: $name [--help]

VANTA wraps upstream zara (components/zara) via /opt/vanta/lib/python.
Full functionality needs zara's optional dependencies (see the notice above);
this stub only answers --help so packagers and tests can probe offline.
USAGE
    exit 0
    ;;
  *)
    exit 1
    ;;
esac
WRAPPER
  chmod 0755 "$out"
}

write_all_vanta_wrappers() {
  local bindir="$1"
  # entrypoints per components/zara/setup.py console_scripts; zara.wake has
  # no __main__ guard, so it is invoked via its main() function directly.
  write_vanta_wrapper vanta         zara.__main__    '-m zara' "$bindir"
  write_vanta_wrapper vanta-server  zara.server      '-m zara.server' "$bindir"
  write_vanta_wrapper vanta-desktop zara.desktop.app '-m zara.desktop.app' "$bindir"
  write_vanta_wrapper vanta-wake    zara.wake        "-c 'import sys; from zara.wake import main; sys.exit(main())'" "$bindir"
  write_vanta_wrapper vanta-dictate zara.dictate     '-m zara.dictate' "$bindir"
}

# ---------------------------------------------------------------------------
# systemd units — modeled on nix/modules/starintel-server.nix and
# distro/vanta/module.nix hardening. /opt ExecStart paths. No unit is enabled
# or started by any package script (privacy: no autostart).
write_vanta_units() {
  local dir="$1"
  mkdir -p "$dir"
  cat > "$dir/vanta-server.service" <<'EOF'
[Unit]
Description=VANTA server daemon (StarIntel agent distribution)
Documentation=file:/usr/share/doc/vanta/README.XDG.md
After=network-online.target
Wants=network-online.target

[Service]
Type=exec
DynamicUser=yes
StateDirectory=vanta
RuntimeDirectory=vanta
Environment=XDG_CONFIG_HOME=/var/lib/vanta/config
Environment=XDG_DATA_HOME=/var/lib/vanta/data
Environment=XDG_STATE_HOME=/var/lib/vanta/state
Environment=XDG_CACHE_HOME=/var/lib/vanta/cache
Environment=VANTA_NO_PROVIDER=1
ExecStart=/opt/vanta/bin/vanta-server
Restart=on-failure
RestartSec=5
NoNewPrivileges=yes
ProtectSystem=strict
ProtectHome=yes
PrivateTmp=yes
PrivateDevices=yes
ProtectKernelTunables=yes
ProtectKernelModules=yes
ProtectControlGroups=yes
RestrictAddressFamilies=AF_INET AF_INET6 AF_UNIX
LockPersonality=yes

[Install]
WantedBy=multi-user.target
EOF
  # wake is double-gated: never auto-enabled AND requires an explicit
  # opt-in marker file before systemd will even consider starting it.
  cat > "$dir/vanta-wake.service" <<'EOF'
[Unit]
Description=VANTA wake-word listener (opt-in; microphone access)
Documentation=file:/usr/share/doc/vanta/README.XDG.md
ConditionPathExists=/etc/vanta/wake.enabled
After=vanta-server.service
Requires=vanta-server.service

[Service]
Type=exec
DynamicUser=yes
SupplementaryGroups=audio
StateDirectory=vanta-wake
Environment=XDG_CONFIG_HOME=/var/lib/vanta/config
Environment=XDG_DATA_HOME=/var/lib/vanta-wake/data
Environment=XDG_STATE_HOME=/var/lib/vanta-wake/state
Environment=XDG_CACHE_HOME=/var/lib/vanta-wake/cache
Environment=VANTA_NO_PROVIDER=1
ExecStart=/opt/vanta/bin/vanta-wake
Restart=on-failure
RestartSec=5
NoNewPrivileges=yes
ProtectSystem=strict
ProtectHome=yes
PrivateTmp=yes
PrivateDevices=no
ProtectKernelTunables=yes
ProtectKernelModules=yes
ProtectControlGroups=yes
RestrictAddressFamilies=AF_INET AF_INET6 AF_UNIX
LockPersonality=yes

[Install]
WantedBy=multi-user.target
EOF
}

write_starintel_server_unit() {
  local dir="$1"
  mkdir -p "$dir"
  cat > "$dir/starintel-server.service" <<'EOF'
[Unit]
Description=StarIntel Server
After=network-online.target
Wants=network-online.target

[Service]
Type=exec
DynamicUser=yes
StateDirectory=starintel
CacheDirectory=starintel
RuntimeDirectory=starintel
Environment=STAR_SERVER_HTTP_HOST=127.0.0.1
Environment=STAR_SERVER_HTTP_PORT=5000
ExecStart=/opt/starintel/bin/starintel-server
Restart=on-failure
RestartSec=5
NoNewPrivileges=yes
ProtectSystem=strict
ProtectHome=yes
PrivateTmp=yes
PrivateDevices=yes
ProtectKernelTunables=yes
ProtectKernelModules=yes
ProtectControlGroups=yes
RestrictAddressFamilies=AF_INET AF_INET6 AF_UNIX
RestrictNamespaces=yes
LockPersonality=yes
MemoryDenyWriteExecute=no
SystemCallArchitectures=native

[Install]
WantedBy=multi-user.target
EOF
}

# ---------------------------------------------------------------------------
# documentation
write_vanta_docs() {
  local docdir="$1" root
  root="$(universe_root)"
  mkdir -p "$docdir"

  cat > "$docdir/copyright" <<'EOF'
Format: https://www.debian.org/doc/packaging-manuals/copyright-format/1.0/
Upstream-Name: zara
Source: pinned as components/zara in starintel-universe (upstream lost-rob0t/zara)
Disclaimer: VANTA is the StarIntel distribution identity of Zara
 (GPL-compatible packaging; see components/zara for upstream licensing).

Files: opt/vanta/lib/python/zara/* and opt/vanta/lib/python/share/zarathushtra/*
Copyright: nsaspy and the Zara authors
License: GPL-3.0-only
 The upstream repository ships the GNU General Public License v3 as its
 LICENSE file (git commit "add gpl"); setuptools metadata in setup.py still
 declares an MIT classifier — an upstream inconsistency. This packaging
 treats the effective license as GPL-3.0-only (GPL-compatible).
 On Debian systems, the full text is available at /usr/share/common-licenses/GPL-3.

Files: opt/vanta/bin/vanta* wrappers, systemd units, desktop files, icon,
 default config and everything else under distro/vanta/
Copyright: 2026 StarIntel / nsaspy <nsaspy@fedora.email>
License: MIT
 Permission is hereby granted, free of charge, to any person obtaining a
 copy of this software and associated documentation files (the "Software"),
 to deal in the Software without restriction, including without limitation
 the rights to use, copy, modify, merge, publish, distribute, sublicense,
 and/or sell copies of the Software, and to permit persons to whom the
 Software is furnished to do so, subject to the following conditions:
 .
 The above copyright notice and this permission notice shall be included
 in all copies or substantial portions of the Software.
 .
 THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL
 THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
 FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
 DEALINGS IN THE SOFTWARE.
EOF

  cat > "$docdir/README.XDG.md" <<'EOF'
# VANTA and XDG — no `$HOME` dotdirs

VANTA (the StarIntel distribution identity of Zara) stores *all* per-user
state inside the XDG base directories. The packages never create legacy
dot-directories such as `~/.zara` or `~/.zarathushtra`.

## User sessions

Every `/opt/vanta/bin/vanta*` wrapper bootstraps:

| purpose | path |
|---------|------|
| config   | `$XDG_CONFIG_HOME/vanta` (default `~/.config/vanta`) |
| data     | `$XDG_DATA_HOME/vanta` (default `~/.local/share/vanta`) |
| state    | `$XDG_STATE_HOME/vanta` (default `~/.local/state/vanta`) |
| cache    | `$XDG_CACHE_HOME/vanta` (default `~/.cache/vanta`) |

A default `config.toml` is seeded on first run from
`/opt/vanta/share/vanta/defaults/config.toml` (never overwritten).

## The zarathushtra -> vanta bridge

Upstream zara reads and writes `$XDG_*_HOME/zarathushtra`. To keep every
byte of state in the canonical `vanta` locations *without* patching
upstream, the wrappers create the symlink

    $XDG_CONFIG_HOME/zarathushtra -> vanta

inside each XDG tree (config, data, state, cache) on every launch. The
symlink always lives *inside* an XDG directory; nothing is ever placed
directly under `$HOME`. An upstream rename of the directory will let this
bridge be dropped later.

## System services

When (and only when) an administrator manually enables them, the packaged
units confine the daemon to `/var/lib/vanta` (vanta-server) and
`/var/lib/vanta-wake` (vanta-wake) via `StateDirectory=` with the same XDG
environment mapping. No package script enables or starts any unit.

## Opt-in wake listener

Wake-word listening (microphone) requires the marker file
`/etc/vanta/wake.enabled` (unit `ConditionPathExists=`) **and** manual
`systemctl enable --now vanta-wake.service`. It is off by default.
EOF
}

write_starintel_docs() {
  local docdir="$1"
  mkdir -p "$docdir"
  cat > "$docdir/copyright" <<'EOF'
Format: https://www.debian.org/doc/packaging-manuals/copyright-format/1.0/
Upstream-Name: starintel-universe
Source: pinned submodules components/star-kb and components/star-lang in
 starintel-universe (git.starintel.actor)

Files: opt/starintel/lib/star-kb/* (from components/star-kb)
Copyright: StarIntel / nsaspy
License: MIT

Files: opt/starintel/bin/* wrappers, universe scripts and everything else
Copyright: 2026 StarIntel / nsaspy <nsaspy@fedora.email>
License: MIT
 Permission is hereby granted, free of charge, to any person obtaining a
 copy of this software and associated documentation files (the "Software"),
 to deal in the Software without restriction, including without limitation
 the rights to use, copy, modify, merge, publish, distribute, sublicense,
 and/or sell copies of the Software, and to permit persons to whom the
 Software is furnished to do so, subject to the following conditions:
 .
 The above copyright notice and this permission notice shall be included
 in all copies or substantial portions of the Software.
 .
 THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL
 THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
 FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
 DEALINGS IN THE SOFTWARE.
EOF
}

# ---------------------------------------------------------------------------
# vanta share payload: defaults config, desktop entries, icon.
# Prefers the nix-built share/ tree when the CI vanta build is present
# (VANTA_BUILD_DIR, default /tmp/opencode/vanta-build); identical content
# lives in distro/vanta and is used otherwise.
stage_vanta_share() {
  local staging="$1" root build share_src
  root="$(universe_root)"
  build="${VANTA_BUILD_DIR:-/tmp/opencode/vanta-build}"
  if [ -d "$build/share" ]; then
    share_src="$build/share"
  else
    echo "common.sh: vanta nix build dir not found ($build);" >&2
    echo "common.sh: staging share/ payload from distro/vanta sources directly." >&2
    share_src=""
  fi

  mkdir -p "$staging/opt/vanta/share/vanta/defaults" \
           "$staging/usr/share/applications" \
           "$staging/usr/share/icons/hicolor/scalable/apps"

  local config_src="$root/distro/vanta/config/vanta-default.toml"
  local icon_src="$root/distro/vanta/branding/vanta.svg"
  if [ -n "$share_src" ]; then
    [ -f "$share_src/vanta/defaults/config.toml" ] && config_src="$share_src/vanta/defaults/config.toml"
    [ -f "$share_src/icons/hicolor/scalable/apps/vanta.svg" ] && icon_src="$share_src/icons/hicolor/scalable/apps/vanta.svg"
  fi
  # desktop entries ALWAYS come from distro/vanta sources: the nix build dir's
  # copies have already had @BIN@ substituted with /nix/store paths by
  # substituteInPlace and are unusable outside nix.

  for f in "$config_src" "$root/distro/vanta/desktop/vanta-desktop.desktop" \
           "$root/distro/vanta/desktop/vanta-console.desktop" "$icon_src"; do
    [ -f "$f" ] || { echo "common.sh: required distro/vanta source missing: $f" >&2; return 1; }
  done

  install -m 0644 "$config_src" "$staging/opt/vanta/share/vanta/defaults/config.toml"
  for desktop in vanta-desktop vanta-console; do
    sed 's#@BIN@#/opt/vanta/bin#g' "$root/distro/vanta/desktop/$desktop.desktop" \
      > "$staging/usr/share/applications/$desktop.desktop"
  done
  install -m 0644 "$icon_src" "$staging/usr/share/icons/hicolor/scalable/apps/vanta.svg"
}

# ---------------------------------------------------------------------------
# starintel tooling: star-kb scripts, universe scripts, starlang if built.
stage_starintel_tools() {
  local staging="$1" root tool
  root="$(universe_root)"

  [ -d "$root/components/star-kb/scripts" ] || {
    echo "common.sh: components/star-kb/scripts missing — cannot stage starintel." >&2
    return 1
  }
  mkdir -p "$staging/opt/starintel/lib/star-kb" "$staging/opt/starintel/bin"
  cp -a "$root/components/star-kb/scripts" "$staging/opt/starintel/lib/star-kb/scripts"
  [ -f "$root/components/star-kb/rage.toml" ] && \
    cp -a "$root/components/star-kb/rage.toml" "$staging/opt/starintel/lib/star-kb/"

  # wrappers mirroring nix/packages/star-kb.nix (star-kb-$tool).
  # validate-docs is exposed canonically as star-kb-validate (with a
  # star-kb-validate-docs compat alias matching the nix naming).
  for tool in save-research implement mark-design task_steward sync validate-docs; do
    if [ -f "$staging/opt/starintel/lib/star-kb/scripts/$tool.py" ]; then
      local wname="star-kb-$tool"
      [ "$tool" = "validate-docs" ] && wname="star-kb-validate"
      cat > "$staging/opt/starintel/bin/$wname" <<EOF
#!/usr/bin/env bash
# $wname — star-kb tooling wrapper, generated by starintel-universe packaging.
exec python3 /opt/starintel/lib/star-kb/scripts/$tool.py "\$@"
EOF
      chmod 0755 "$staging/opt/starintel/bin/$wname"
      if [ "$tool" = "validate-docs" ]; then
        ln -sf "$wname" "$staging/opt/starintel/bin/star-kb-validate-docs"
      fi
    fi
  done

  # universe control-plane scripts (scripts/*.sh)
  if [ -d "$root/scripts" ]; then
    for script in "$root/scripts"/*.sh; do
      [ -e "$script" ] || continue
      install -m 0755 "$script" "$staging/opt/starintel/bin/"
    done
  fi

  # starlang wrapper — only when a star-lang build is present
  # (VANTA_STARLANG_BUILD, default /tmp/opencode/starlang-build, providing
  # bin/starlang). Never a placeholder.
  local starlang_build="${VANTA_STARLANG_BUILD:-/tmp/opencode/starlang-build}"
  if [ -x "$starlang_build/bin/starlang" ]; then
    mkdir -p "$staging/opt/starintel/lib/starlang"
    cp -a "$starlang_build/." "$staging/opt/starintel/lib/starlang/"
    cat > "$staging/opt/starintel/bin/starlang" <<'EOF'
#!/usr/bin/env bash
# starlang — wrapper around the star-lang build, generated by starintel-universe packaging.
exec /opt/starintel/lib/starlang/bin/starlang "$@"
EOF
    chmod 0755 "$staging/opt/starintel/bin/starlang"
    echo "common.sh: staged starlang from $starlang_build" >&2
  else
    echo "common.sh: starlang build not found ($starlang_build) — skipping starlang wrapper." >&2
  fi
}

# ---------------------------------------------------------------------------
# requirements.txt for the optional heavy deps (from the wheel METADATA that
# pip wrote — single source of truth, no duplicated setup.py parsing).
write_zara_requirements() {
  local staging="$1" metadata
  metadata="$(find "$staging/opt/vanta/lib/python" -maxdepth 2 -name METADATA \
    -path '*.dist-info/*' 2>/dev/null | head -n1)"
  [ -n "$metadata" ] || return 0
  grep '^Requires-Dist:' "$metadata" | sed -e 's/^Requires-Dist: //' -e 's/;.*//' \
    > "$staging/opt/vanta/share/vanta/requirements.txt"
}

# ---------------------------------------------------------------------------
# collect_staging <dir> — the full universe staging tree.
collect_staging() {
  local staging="$1" root
  root="$(universe_root)"
  mkdir -p "$(dirname "$staging")"
  staging="$(cd "$(dirname "$staging")" && pwd)/$(basename "$staging")"
  rm -rf "$staging"
  mkdir -p "$staging"

  echo "common.sh: staging vanta (python source from pinned components/zara)..." >&2
  stage_zara_python "$staging/opt/vanta/lib/python"
  [ -d "$staging/opt/vanta/lib/python/zara" ] || {
    echo "common.sh: pip staging of zara failed — refusing to build a placeholder package." >&2
    return 1
  }
  # the wheel also installs console scripts + share/zarathushtra data files
  # into the pip target; the distro packages use their own /opt wrappers, so
  # drop the pip bin/ to avoid shadowing (share/zarathushtra stays — zara's
  # prolog loader probes <prefix>/share/zarathushtra).
  rm -rf "$staging/opt/vanta/lib/python/bin"

  stage_vanta_share "$staging"
  write_all_vanta_wrappers "$staging/opt/vanta"
  write_zara_requirements "$staging"

  echo "common.sh: staging starintel tooling..." >&2
  stage_starintel_tools "$staging"

  write_vanta_units "$staging/lib/systemd/system"
  write_starintel_server_unit "$staging/lib/systemd/system"

  write_vanta_docs "$staging/usr/share/doc/vanta"
  write_starintel_docs "$staging/usr/share/doc/starintel"

  echo "common.sh: staging tree complete at $staging" >&2
}

# ---------------------------------------------------------------------------
# write_manifest <dist-dir> <kind> <file...>
# Deterministic JSON: universe version, pinned submodule SHAs (parsed from
# `git submodule status`), package names and sha256 of each artifact.
write_manifest() {
  local dist="$1" kind="$2"; shift 2
  local root; root="$(universe_root)"
  local manifest="$dist/packaging-manifest.json"
  mkdir -p "$dist"
  python3 - "$root" "$kind" "$manifest" "$@" <<'PY'
import hashlib, json, subprocess, sys
from pathlib import Path

root, kind, manifest_path = sys.argv[1], sys.argv[2], sys.argv[3]
artifacts = sys.argv[4:]

def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as fh:
        for chunk in iter(lambda: fh.read(1 << 16), b""):
            h.update(chunk)
    return h.hexdigest()

components, raw_status = {}, []
try:
    out = subprocess.run(
        ["git", "-C", root, "submodule", "status"],
        check=True, capture_output=True, text=True,
    ).stdout
except Exception:
    out = ""
for line in out.splitlines():
    fields = line.split()
    if len(fields) < 2:
        continue
    raw_status.append(line.strip())
    sha = fields[0]
    flags = ""
    while sha and sha[0] in "-+U":
        flags += sha[0]
        sha = sha[1:]
    path = fields[1]
    describe = line[line.find("(") + 1 : line.rfind(")")] if "(" in line else ""
    components[path] = {"sha": sha, "describe": describe, "flags": flags or None}

packages = []
for artifact in artifacts:
    p = Path(artifact)
    packages.append({
        "name": p.name,
        "kind": kind,
        "bytes": p.stat().st_size,
        "sha256": sha256(str(p)),
    })

def release_version():
    manifest_json = Path(root) / "manifest.json"
    if manifest_json.exists():
        try:
            data = json.loads(manifest_json.read_text(encoding="utf-8"))
            for key in ("version", "release_version", "schema_version"):
                value = data.get(key) if isinstance(data, dict) else None
                if isinstance(value, str) and value.strip():
                    parts = value.strip().split(".")
                    return ".".join(parts[:2])
        except Exception:
            pass
    import datetime
    return "0." + datetime.date.today().strftime("%Y%m%d")

doc = {
    "schema": 1,
    "universe": "starintel-universe",
    "version": release_version(),
    "components": components,
    "submodule_status": raw_status,
    "packages": packages,
}
Path(manifest_path).write_text(json.dumps(doc, indent=2, sort_keys=True) + "\n", encoding="utf-8")
print(f"common.sh: manifest written to {manifest_path}", file=sys.stderr)
PY
}
