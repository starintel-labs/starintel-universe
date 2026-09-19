# Home Manager module for StarIntel users (generic defaults only).
#
# Personal configuration (private secrets, machine-specific hosts, the
# full personal desktop) stays in each user's own dotfiles checkout and
# composes ON TOP of this module. Nothing personal ships here.
{
  config,
  lib,
  pkgs,
  ...
}:

with lib;
{
  options.starintel.user = {
    enable = mkEnableOption "generic StarIntel home defaults";

    dotfiles.enable = mkOption {
      type = types.bool;
      default = false;
      description = "Generic StarIntel shell/editor/git defaults";
    };

    vanta.enable = mkOption {
      type = types.bool;
      default = true;
      description = "VANTA user configuration and XDG bridge";
    };

    tools.enable = mkOption {
      type = types.bool;
      default = true;
      description = "Install the StarIntel user CLI tool set";
    };
  };

  config =
    let
      # Tools come from the universe overlay when present; absent tools
      # degrade gracefully instead of breaking evaluation.
      maybeTool = name: if pkgs ? ${name} then [ pkgs.${name} ] else [ ];
      tools =
        (maybeTool "star-kb")
        ++ (maybeTool "star-lang")
        ++ (maybeTool "prolog-rlm")
        ++ (maybeTool "star-cl");
    in
    mkIf config.starintel.user.enable {
      home.packages = optionals config.starintel.user.tools.enable tools;

      xdg = {
        enable = true;
        configFile."starintel/starintel.conf".text = "# generic defaults\n";
        configFile."quasar/quasar.conf".text = ''
          starintel_url = "http://127.0.0.1:5000"
        '';
      };

      programs.git = mkIf config.starintel.user.dotfiles.enable {
        enable = true;
        config = {
          init.defaultBranch = "main";
          core.excludesfile = "${config.xdg.configHome}/git/ignore";
        };
      };
    };
}
