# Quasar — control plane + UI NixOS service module.
{
  config,
  lib,
  pkgs,
  ...
}:

with lib;
{
  options.services.quasar = {
    enable = mkEnableOption "Quasar control plane and web UI";

    package = mkOption {
      type = types.package;
      default = pkgs.callPackage (
        { ... }:
        throw ''
          services.quasar.package is not set.
          The universe sets it automatically via the starintel umbrella module;
          when importing this module standalone, pass the pinned package.
        ''
      ) { };
      defaultText = "starintel-flake.packages.<system>.quasar";
      description = "quasar-server package (bundled UI)";
    };

    host = mkOption {
      type = types.str;
      default = "127.0.0.1";
    };
    httpPort = mkOption {
      type = types.port;
      default = 8080;
    };
    wsPort = mkOption {
      type = types.port;
      default = 8081;
    };

    starintelServerUrl = mkOption {
      type = types.str;
      default = "http://127.0.0.1:5000";
      description = "Upstream StarIntel Server API URL";
    };
  };

  config = mkIf config.services.quasar.enable {
    systemd.services.quasar = {
      description = "Quasar control plane";
      wantedBy = [ "multi-user.target" ];
      after = [
        "network-online.target"
        "starintel-server.service"
      ];
      wants = [ "network-online.target" ];

      environment = {
        QUASAR_HTTP_HOST = config.services.quasar.host;
        QUASAR_HTTP_PORT = toString config.services.quasar.httpPort;
        QUASAR_WS_PORT = toString config.services.quasar.wsPort;
        STARINTEL_URL = config.services.quasar.starintelServerUrl;
      };

      serviceConfig = {
        Type = "exec";
        DynamicUser = true;
        StateDirectory = "quasar";
        RuntimeDirectory = "quasar";
        NoNewPrivileges = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
        PrivateDevices = true;
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

    services.nginx = {
      enable = mkDefault true;
      virtualHosts."quasar.local" = {
        locations."/" = {
          proxyPass = "http://${config.services.quasar.host}:${toString config.services.quasar.httpPort}";
          proxyWebsockets = true;
        };
      };
    };
  };
}
