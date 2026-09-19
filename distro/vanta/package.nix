# VANTA distribution package — StarIntel's identity for upstream Zara.
#
# Wraps the pinned upstream zara binaries behind vanta* names and installs
# the XDG compatibility bridge: upstream reads $XDG_*_HOME/zarathushtra;
# we expose symlinks zarathushtra -> vanta INSIDE the XDG trees so all
# state lands in the canonical vanta/ locations without patching upstream
# yet (an upstream rename may replace this bridge later).
{
  lib,
  stdenv,
  buildEnv,
  makeWrapper,
  bash,
  zaraPkgs ? { },
  ...
}:

let
  inherit (lib) optionalString;

  # upstream shims: name -> zara package attr
  shims = {
    vanta = "zara-cli";
    vanta-server = "zara-server";
    vanta-desktop = "zara-desktop";
    vanta-wake = "zara-wake";
    vanta-dictate = "zara-dictate";
  };
in
stdenv.mkDerivation rec {
  pname = "vanta";
  version = (zaraPkgs.zarathushtra.version or "2.0.0");

  dontUnpack = true;
  dontBuild = true;

  nativeBuildInputs = [ makeWrapper ];

  installPhase = ''
    mkdir -p $out/bin $out/share/applications $out/share/icons/hicolor/scalable/apps $out/share/vanta/defaults

    # XDG bridge + exec shim
    makeBridge() {
      cat > $out/bin/.vanta-bridge <<'BRIDGE'
    #!/usr/bin/env bash
    # zarathushtra -> vanta compatibility bridge (inside XDG trees only)
    ensure_dir_link() {
      base="$1"; sub="$2"; name="$3"
      [ -z "''${!base:-}" ] && return 0
      dir="''${!base}"
      mkdir -p "$dir/$sub"
      if [ -e "$dir/$sub/$name" ] && [ ! -L "$dir/$sub/$name" ]; then
        return 0
      fi
      ln -sfn "vanta" "$dir/$sub/$name" 2>/dev/null || true
    }
    ensure_dir_link XDG_CONFIG_HOME "" zarathushtra
    ensure_dir_link XDG_DATA_HOME "" zarathushtra
    ensure_dir_link XDG_STATE_HOME "" zarathushtra
    ensure_dir_link XDG_CACHE_HOME "" zarathushtra
    BRIDGE
      chmod +x $out/bin/.vanta-bridge
    }
    makeBridge

    write_shim() {
      local vname="$1"; local target="$2"
      cat > "$out/bin/$vname" <<EOF
    #!/usr/bin/env bash
    export XDG_CONFIG_HOME="''${XDG_CONFIG_HOME:-\$HOME/.config}"
    export XDG_DATA_HOME="''${XDG_DATA_HOME:-\$HOME/.local/share}"
    export XDG_STATE_HOME="''${XDG_STATE_HOME:-\$HOME/.local/state}"
    export XDG_CACHE_HOME="''${XDG_CACHE_HOME:-\$HOME/.cache}"
    mkdir -p "\$XDG_CONFIG_HOME/vanta" "\$XDG_DATA_HOME/vanta" "\$XDG_STATE_HOME/vanta" "\$XDG_CACHE_HOME/vanta"
    if [ ! -e "\$XDG_CONFIG_HOME/vanta/config.toml" ] && [ -e "$out/share/vanta/defaults/config.toml" ]; then
      install -m 0644 "$out/share/vanta/defaults/config.toml" "\$XDG_CONFIG_HOME/vanta/config.toml" 2>/dev/null || true
    fi
    exec "$out/bin/.vanta-bridge" || true
    exec "$target" "\$@"
    EOF
      chmod +x "$out/bin/$vname"
    }

    ${optionalString (zaraPkgs ? zara-cli) ''write_shim vanta "${zaraPkgs.zara-cli}/bin/zara"''}
    ${optionalString (
      zaraPkgs ? zara-server
    ) ''write_shim vanta-server "${zaraPkgs.zara-server}/bin/zara-server"''}
    ${optionalString (
      zaraPkgs ? zara-desktop
    ) ''write_shim vanta-desktop "${zaraPkgs.zara-desktop}/bin/zara-desktop"''}
    ${optionalString (
      zaraPkgs ? zara-wake
    ) ''write_shim vanta-wake "${zaraPkgs.zara-wake}/bin/zara-wake"''}
    ${optionalString (
      zaraPkgs ? zara-dictate
    ) ''write_shim vanta-dictate "${zaraPkgs.zara-dictate}/bin/zara-dictate"''}

    install -m 0644 ${./config/vanta-default.toml} $out/share/vanta/defaults/config.toml
    install -m 0644 ${./desktop/vanta-desktop.desktop} $out/share/applications/vanta-desktop.desktop
    install -m 0644 ${./desktop/vanta-console.desktop} $out/share/applications/vanta-console.desktop
    install -m 0644 ${./branding/vanta.svg} $out/share/icons/hicolor/scalable/apps/vanta.svg
    substituteInPlace $out/share/applications/*.desktop \
      --replace @BIN@ $out/bin
  '';

  passthru = {
    upstream = "lost-rob0t/zara";
  };

  meta = with lib; {
    description = "VANTA — the StarIntel agent distribution (wraps upstream Zara)";
    license = licenses.mit;
    mainProgram = "vanta";
  };
}
