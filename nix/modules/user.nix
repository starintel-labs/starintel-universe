# Default user environment for StarIntel systems.
#
# Two layers, kept strictly separate:
#   1. GENERIC StarIntel defaults (shipped here): XDG environment, default
#      starintel/vanta/quasar config templates, editor/git XDG hygiene.
#   2. PERSONAL configuration: never shipped. Users bring their own
#      dotfiles checkout (e.g. the upstream dotfiles component) through
#      Home Manager; see nix/home/default.nix.
{
  config,
  lib,
  pkgs,
  ...
}:

with lib;
{
  options.starintel.user = {
    enable = mkEnableOption "generic StarIntel user defaults";

    dotfiles = {
      enable = mkOption {
        type = types.bool;
        default = false;
        description = "Install generic (non-personal) StarIntel shell/git/editor defaults";
      };
    };

    vanta.enable = mkOption {
      type = types.bool;
      default = true;
      description = "Install VANTA user-level configuration defaults";
    };
  };

  config = mkIf config.starintel.user.enable {
    # Generic templates, no secrets, no machine-specific values.
    environment.etc."xdg/starintel/starintel.conf".text = ''
      # Generic StarIntel defaults (XDG_CONFIG_HOME/starintel/starintel.conf)
      # Personal overrides belong in the user's own config, not here.
    '';

    environment.etc."xdg/quasar/quasar.conf".text = ''
      # Generic Quasar defaults
      starintel_url = "http://127.0.0.1:5000"
    '';

    environment.etc."xdg/vanta/config.toml".text = ''
      # Generic VANTA defaults (see distro/vanta/config for the full template)
      # LLM provider defaults to local ollama so the system is fully usable
      # offline / without any provider credentials.
      [llm]
      provider = "ollama"

      [desktop]
      enabled = true

      [wake]
      enabled = false
    '';

    environment.shellInit = mkIf config.starintel.user.dotfiles.enable ''
      export XDG_CONFIG_HOME="''${XDG_CONFIG_HOME:-$HOME/.config}"
      export XDG_DATA_HOME="''${XDG_DATA_HOME:-$HOME/.local/share}"
      export XDG_STATE_HOME="''${XDG_STATE_HOME:-$HOME/.local/state}"
      export XDG_CACHE_HOME="''${XDG_CACHE_HOME:-$HOME/.cache}"
      export STARINTEL_HOME="$XDG_DATA_HOME/starintel"
    '';
  };
}
