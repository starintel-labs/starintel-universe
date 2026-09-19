# VANTA — the StarIntel distribution identity of Zara.
#
# Upstream implementation stays lost-rob0t/zara; this module wires the
# packaged shims into systemd services with hardening. Wake listening is
# opt-in only.
{
  config,
  lib,
  pkgs,
  ...
}:

with lib;
{
  options.services.vanta = {
    enable = mkEnableOption "the VANTA agent distribution";

    package = mkOption {
      type = types.package;
      default = pkgs.callPackage (
        { ... }:
        throw ''
          services.vanta.package is not set.
          The universe sets it automatically via the starintel umbrella module;
          when importing this module standalone, pass the VANTA distribution
          package (distro/vanta/package.nix).
        ''
      ) { };
      defaultText = "starintel-flake.packages.<system>.vanta";
      description = "VANTA distribution package (wraps upstream zara)";
    };

    user = mkOption {
      type = types.str;
      default = "vanta";
      description = "Dedicated system user for the VANTA server daemon";
    };

    desktop.enable = mkOption {
      type = types.bool;
      default = false;
      description = "Install desktop entries and user-session launcher";
    };

    server.enable = mkOption {
      type = types.bool;
      default = false;
      description = "Run vanta-server as a system service";
    };

    wake.enable = mkOption {
      type = types.bool;
      default = false;
      description = "Wake-word listener (microphone access) — explicit opt-in";
    };

    secretsFile = mkOption {
      type = types.nullOr types.path;
      default = null;
      description = "Provider credentials for the daemon (never in the store)";
    };
  };

  config = mkIf config.services.vanta.enable {
    users.users = mkIf config.services.vanta.server.enable {
      ${config.services.vanta.user} = {
        isSystemUser = true;
        group = config.services.vanta.user;
        home = "/var/lib/vanta";
        createHome = true;
      };
    };
    users.groups = mkIf config.services.vanta.server.enable {
      ${config.services.vanta.user} = { };
    };

    environment.systemPackages = [
      config.services.vanta.package
    ]
    ++ optionals config.services.vanta.desktop.enable [ config.services.vanta.package ];

    systemd.services.vanta-server = mkIf config.services.vanta.server.enable {
      description = "VANTA server daemon";
      wantedBy = [ "multi-user.target" ];
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];

      serviceConfig = {
        Type = "exec";
        User = config.services.vanta.user;
        Group = config.services.vanta.user;
        StateDirectory = "vanta";
        Environment = [
          "XDG_CONFIG_HOME=/var/lib/vanta/config"
          "XDG_DATA_HOME=/var/lib/vanta/data"
          "XDG_STATE_HOME=/var/lib/vanta/state"
          "XDG_CACHE_HOME=/var/lib/vanta/cache"
          "XDG_RUNTIME_DIR=/run/vanta"
        ];
        EnvironmentFile = mkIf (config.services.vanta.secretsFile != null) [
          (toString config.services.vanta.secretsFile)
        ];
        RuntimeDirectory = "vanta";
        ExecStart = "${config.services.vanta.package}/bin/vanta-server";
        Restart = "on-failure";
        NoNewPrivileges = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
        PrivateDevices = true; # audio only for the wake/dictate path
        ProtectKernelTunables = true;
        ProtectKernelModules = true;
        ProtectControlGroups = true;
        RestrictAddressFamilies = [
          "AF_INET"
          "AF_INET6"
          "AF_UNIX"
        ];
        LockPersonality = true;
      };
    };

    systemd.services.vanta-wake = mkIf config.services.vanta.wake.enable {
      description = "VANTA wake-word listener (opt-in)";
      wantedBy = [ "multi-user.target" ];
      after = [ "vanta-server.service" ];
      requires = [ "vanta-server.service" ];

      serviceConfig = {
        Type = "exec";
        User = config.services.vanta.user;
        Group = config.services.vanta.user;
        SupplementaryGroups = [ "audio" ];
        Environment = [
          "XDG_CONFIG_HOME=/var/lib/vanta/config"
          "XDG_DATA_HOME=/var/lib/vanta/data"
          "XDG_STATE_HOME=/var/lib/vanta/state"
          "XDG_CACHE_HOME=/var/lib/vanta/cache"
        ];
        ExecStart = "${config.services.vanta.package}/bin/vanta-wake";
        Restart = "on-failure";
        NoNewPrivileges = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
      };
    };
  };
}
