# StarIntel umbrella NixOS module — the canonical distribution interface:
#
#   services.starintel = {
#     enable = true;
#     server.enable = true;
#     quasar.enable = true;
#     vanta = {
#       enable = true;
#       desktop.enable = true;
#       server.enable = true;
#       wake.enable = false;
#     };
#   };
#
# Components may always be disabled individually through their own
# services.* modules; this module only composes defaults.
{
  config,
  lib,
  pkgs,
  starintel-flake,
  ...
}:

with lib;
{
  imports = [
    ./xdg.nix
    ./user.nix
    ./starintel-server.nix
    ./quasar.nix
    ../../distro/vanta/module.nix
  ];

  options.services.starintel = {
    enable = mkEnableOption "the StarIntel distribution services";

    server.enable = mkOption {
      type = types.bool;
      default = false;
      description = "Run StarIntel Server (API, actor routing, event log)";
    };

    quasar.enable = mkOption {
      type = types.bool;
      default = false;
      description = "Run the Quasar control plane and UI";
    };

    vanta = {
      enable = mkOption {
        type = types.bool;
        default = false;
        description = "Install the VANTA agent distribution";
      };
      desktop.enable = mkOption {
        type = types.bool;
        default = false;
        description = "VANTA desktop application and launcher";
      };
      server.enable = mkOption {
        type = types.bool;
        default = false;
        description = "VANTA server daemon (system service)";
      };
      wake.enable = mkOption {
        type = types.bool;
        default = false;
        description = "Wake-word listener. NEVER enabled without explicit user choice.";
      };
    };
  };

  config = {
    starintel.xdg.enable = mkDefault true;

    services.starintel-server = mkIf config.services.starintel.server.enable {
      enable = true;
      package = mkDefault starintel-flake.packages.${pkgs.system}.starintel-server;
    };

    services.quasar = mkIf config.services.starintel.quasar.enable {
      enable = true;
      package = mkDefault starintel-flake.packages.${pkgs.system}.quasar;
    };

    services.vanta = mkIf config.services.starintel.vanta.enable {
      enable = true;
      package = mkDefault starintel-flake.packages.${pkgs.system}.vanta;
      desktop.enable = mkDefault config.services.starintel.vanta.desktop.enable;
      server.enable = mkDefault config.services.starintel.vanta.server.enable;
      wake.enable = mkDefault config.services.starintel.vanta.wake.enable;
    };
  };
}
