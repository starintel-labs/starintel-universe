# StarIntel server profile — headless full-stack deployment.
{
  config,
  pkgs,
  lib,
  ...
}:

with lib;
{
  imports = [ ./minimal.nix ];

  config = {
    services.starintel = {
      enable = mkDefault true;
      server.enable = mkDefault true;
      quasar.enable = mkDefault true;
      vanta = {
        enable = mkDefault true;
        desktop.enable = mkDefault false;
        server.enable = mkDefault true;
        wake.enable = mkDefault false;
      };
    };

    networking.firewall = {
      enable = mkDefault true;
      allowedTCPPorts = [
        80
        443
      ];
    };

    services.openssh = {
      enable = mkDefault true;
      settings.PasswordAuthentication = false;
    };
  };
}
