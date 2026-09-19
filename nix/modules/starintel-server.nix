# StarIntel Server — NixOS service module.
#
# Runs the pinned starintel-server binary with optional bundled backing
# services (CouchDB, RabbitMQ, Valkey). Secrets are NEVER inlined: the API
# key is referenced through starintel-server.secretsFile (root-only file).
{
  config,
  lib,
  pkgs,
  ...
}:

with lib;
{
  options.services.starintel-server = {
    enable = mkEnableOption "StarIntel Server";

    package = mkOption {
      type = types.package;
      default = pkgs.callPackage (
        { ... }:
        throw ''
          services.starintel-server.package is not set.
          The universe sets it automatically via the starintel umbrella module;
          when importing this module standalone, pass the pinned package.
        ''
      ) { };
      defaultText = "starintel-flake.packages.<system>.starintel-server";
      description = "starintel-server package";
    };

    environment = mkOption {
      type = types.attrsOf types.str;
      default = { };
      description = "Extra environment for the service";
    };

    secretsFile = mkOption {
      type = types.nullOr types.path;
      default = null;
      description = "Root-readable file with secrets (never stored in the Nix store)";
    };

    withCouchDB = mkOption {
      type = types.bool;
      default = true;
    };
    withRabbitMQ = mkOption {
      type = types.bool;
      default = true;
    };
    withValkey = mkOption {
      type = types.bool;
      default = true;
    };
  };

  config = mkIf config.services.starintel-server.enable {
    services.couchdb.enable = config.services.starintel-server.withCouchDB;
    services.rabbitmq.enable = config.services.starintel-server.withRabbitMQ;
    services.redis.enable = config.services.starintel-server.withValkey;

    systemd.services.starintel-server = {
      description = "StarIntel Server";
      wantedBy = [ "multi-user.target" ];
      after = [
        "network-online.target"
      ]
      ++ optionals config.services.starintel-server.withCouchDB [ "couchdb.service" ]
      ++ optionals config.services.starintel-server.withRabbitMQ [ "rabbitmq.service" ]
      ++ optionals config.services.starintel-server.withValkey [ "redis.service" ];
      wants = [ "network-online.target" ];

      serviceConfig = {
        Type = "exec";
        DynamicUser = true;
        StateDirectory = "starintel";
        CacheDirectory = "starintel";
        RuntimeDirectory = "starintel";
        Environment = [
          "STAR_SERVER_HTTP_HOST=127.0.0.1"
          "STAR_SERVER_HTTP_PORT=5000"
        ];
        EnvironmentFile = mkIf (config.services.starintel-server.secretsFile != null) [
          (toString config.services.starintel-server.secretsFile)
        ];
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
        RestrictNamespaces = true;
        LockPersonality = true;
        MemoryDenyWriteExecute = false; # SBCL needs executable heap
        SystemCallArchitectures = "native";
      };
    };
  };
}
