# StarIntel minimal profile — CLI tooling only, no services.
# The base every other profile composes onto.
{
  config,
  pkgs,
  lib,
  starintel-flake,
  ...
}:

with lib;
{
  options.starintel.profile.minimal = {
    enable = mkOption {
      type = types.bool;
      default = true;
      description = "Base StarIntel system (always on for StarIntel profiles)";
    };
    cliTools = mkOption {
      type = types.bool;
      default = true;
      description = "Install the StarIntel CLI tool set";
    };
  };

  config = {
    starintel.xdg.enable = mkDefault true;

    # Generic bootable machine so the non-ISO configurations evaluate; the
    # ISO base overrides these with its own plain-priority definitions.
    fileSystems."/" = mkDefault {
      device = "/dev/disk/by-label/nixos";
      fsType = "ext4";
    };
    boot.loader.grub.devices = mkDefault [ "/dev/vda" ];

    environment.systemPackages = lib.optionals config.starintel.profile.minimal.cliTools (
      [
        starintel-flake.packages.${pkgs.system}.star-kb
        starintel-flake.packages.${pkgs.system}.star-lang
        starintel-flake.packages.${pkgs.system}.prolog-rlm
      ]
      ++ lib.optionals (pkgs.system == "x86_64-linux") [
        starintel-flake.packages.${pkgs.system}.star-cl
      ]
    );

    nix.settings.experimental-features = [
      "nix-command"
      "flakes"
    ];
  };
}
