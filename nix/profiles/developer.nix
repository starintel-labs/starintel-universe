# StarIntel developer profile — desktop plus build tooling.
{
  config,
  pkgs,
  lib,
  ...
}:

with lib;
{
  imports = [ ./desktop.nix ];

  config = {
    environment.systemPackages = with pkgs; [
      sbcl
      nodejs_22
      python3
      nixfmt-rfc-style
      docker-client
      jq
      tmux
      emacs
    ];

    services.openssh.enable = mkDefault true;

    # Builders keep substitutable caches but no binary-caching secrets here.
    nix.settings = {
      experimental-features = [
        "nix-command"
        "flakes"
      ];
      warn-dirty = false;
    };
  };
}
