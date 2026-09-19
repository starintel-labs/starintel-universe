# StarIntel desktop profile — full workstation with all services enabled.
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
    starintel.user.enable = mkDefault true;

    services.starintel = {
      enable = mkDefault true;
      server.enable = mkDefault true;
      quasar.enable = mkDefault true;
      vanta = {
        enable = mkDefault true;
        desktop.enable = mkDefault true;
        server.enable = mkDefault true;
        wake.enable = mkDefault false; # explicit user choice only
      };
    };

    # Desktop environment: light, hardware-acceleration optional.
    services.xserver = {
      enable = mkDefault true;
      displayManager.lightdm.enable = mkDefault true;
      desktopManager.xfce.enable = mkDefault true;
    };

    environment.systemPackages = with pkgs; [
      firefox
      kitty
      xterm
      git
      openssh
      ripgrep
      fd
      file
      htop
      dnsutils
      tcpdump
      swi-prolog
    ];
  };
}
