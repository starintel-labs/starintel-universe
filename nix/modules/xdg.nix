# XDG base-directory conventions for the whole distribution.
#
# Invariant: nothing shipped by StarIntel may create new dot-dirs in $HOME.
# All state lives under the XDG trees; the zarathushtra->vanta compat bridge
# is a symlink INSIDE the XDG tree, never a new $HOME entry.
{
  config,
  lib,
  pkgs,
  ...
}:

with lib;
{
  options.starintel.xdg = {
    enable = mkEnableOption "strict XDG base-directory environment";

    bridgeZarathushtra = mkOption {
      type = types.bool;
      default = true;
      description = ''
        Create compatibility symlinks <literal>$XDG_CONFIG_HOME/zarathushtra -> vanta</literal>
        (and data/state/cache) so legacy Zara paths resolve into the canonical
        VANTA locations during the upstream migration window.
      '';
    };
  };

  config = mkIf config.starintel.xdg.enable {
    environment.sessionVariables = {
      XDG_CONFIG_HOME = "\$HOME/.config";
      XDG_DATA_HOME = "\$HOME/.local/share";
      XDG_STATE_HOME = "\$HOME/.local/state";
      XDG_CACHE_HOME = "\$HOME/.cache";
    };
  };
}
