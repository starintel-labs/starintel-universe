# StarIntel OS ISO fragment — applied on top of the nixpkgs installer base
# (see flake.nix starintel-os, which imports the nixpkgs installation-cd
# module first). Produces a bootable live/installer image:
#   nix build .#starintel-iso
{
  config,
  pkgs,
  lib,
  ...
}:

with lib;
{
  imports = [ ../profiles/desktop.nix ];

  config = {
    # The installer base (installation-device.nix) and the redis module both
    # claim vm.overcommit_memory with plain priority; avoid the collision on
    # the live image by not bundling redis there (leases fall back to local
    # store on the live session).
    services.starintel-server.withValkey = mkForce false;

    # Live image identity
    networking.hostName = mkDefault "starintel-os";
    services.openssh.enable = mkDefault true; # installer base enables ssh

    # The installer user can use the whole desktop preinstalled.
    services.starintel = {
      enable = mkForce true;
      server.enable = mkForce true;
      quasar.enable = mkForce true;
      vanta = {
        enable = mkForce true;
        desktop.enable = mkForce true;
        server.enable = mkForce false; # live session: launch manually
        wake.enable = mkForce false;
      };
    };

    # Autologin for the live session so ISO tests can drive the desktop.
    services.xserver.displayManager.lightdm = {
      autoLogin.enable = mkDefault true;
      autoLogin.user = mkDefault "starintel";
    };
    users.users.starintel = {
      isNormalUser = mkDefault true;
      extraGroups = [
        "wheel"
        "networkmanager"
        "audio"
        "video"
      ];
      initialPassword = mkDefault "starintel"; # live image only; installer prompts to change
      description = "StarIntel live session";
    };

    isoImage = {
      isoBaseName = mkForce "StarIntel-OS";
      makeEfiBootable = mkDefault true;
      makeBiosBootable = mkDefault true;
      squashfsCompression = mkDefault "zstd -Xcompression-level 19";
    };

    # No hardware-specific acceleration requirements: Mesa software
    # rendering is the floor, accelerators enhance.
    hardware.graphics.enable = mkDefault true;
  };
}
