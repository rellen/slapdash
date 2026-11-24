# NixOS module: services.ramshackle runs the Ramshackle server as a systemd
# service, optionally with a local PostgreSQL database.
{ self }:
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.services.ramshackle;

  inherit (lib)
    literalExpression
    mkEnableOption
    mkIf
    mkOption
    optional
    types
    ;

  # Secrets are read at runtime from an absolute path outside the Nix store,
  # which is world-readable.
  secretPath = types.pathWith {
    inStore = false;
    absolute = true;
  };

  localDatabaseUrl = "ecto://${cfg.database.user}@localhost/${cfg.database.name}?socket_dir=/run/postgresql";

  environment = {
    PORT = toString cfg.port;
    POOL_SIZE = toString cfg.database.poolSize;
    # The release writes its generated runtime configuration here. The
    # default, inside the release, is the read-only Nix store.
    RELEASE_TMP = "/run/ramshackle";
    # Erlang distribution on loopback only, so `ramshackle-rpc` and
    # `ramshackle-remote` can reach the running node. epmd and the
    # distribution listener bind 127.0.0.1, and the node is named by IP so
    # nothing depends on how the host name resolves. The cookie is created
    # on first start, readable by the service user only.
    RELEASE_DISTRIBUTION = "name";
    RELEASE_NODE = "ramshackle@127.0.0.1";
    RELEASE_COOKIE_FILE = "/var/lib/ramshackle/cookie";
    ERL_EPMD_ADDRESS = "127.0.0.1";
    ELIXIR_ERL_OPTIONS = "-kernel inet_dist_use_interface {127,0,0,1}";
    LANG = "C.UTF-8";
  }
  // lib.optionalAttrs (cfg.database.url != null) { DATABASE_URL = cfg.database.url; }
  // cfg.environment;

  # Reads the master key from its systemd credential into the environment the
  # release expects, then runs the given release command.
  withSecrets = pkgs.writeShellScript "ramshackle-with-secrets" ''
    set -euo pipefail
    RAMSHACKLE_MASTER_KEY="$(< "$CREDENTIALS_DIRECTORY/master_key")"
    export RAMSHACKLE_MASTER_KEY
    exec "$@"
  '';

  # Admin commands that run `bin/ramshackle` as the service user, with the
  # service's environment, in a transient systemd unit:
  #
  # - `ramshackle-eval EXPR` starts a fresh VM with only what EXPR needs, so
  #   it works whether or not the server is running. Used to onboard root.
  # - `ramshackle-rpc EXPR` runs EXPR inside the running server.
  # - `ramshackle-remote` opens an IEx shell on the running server.
  #
  # rpc and remote reach the server over loopback Erlang distribution with
  # the cookie in /var/lib/ramshackle/cookie.
  adminEnvironment = environment // {
    RELEASE_TMP = "/run/ramshackle-admin";
  };

  releaseCommand =
    {
      name,
      usage,
      command,
      args,
      systemdRunFlags,
    }:
    pkgs.writeShellScriptBin name ''
      set -euo pipefail
      ${lib.optionalString (usage != null) ''
        if [ "$#" -ne 1 ]; then
          echo ${lib.escapeShellArg "usage: ${name} ${usage}"} >&2
          exit 64
        fi
      ''}
      exec ${config.systemd.package}/bin/systemd-run --quiet --wait --collect ${systemdRunFlags} \
        --uid=${cfg.database.user} --gid=${cfg.database.user} \
        --property=LoadCredential=master_key:${cfg.masterKeyFile} \
        --property=StateDirectory=ramshackle \
        --property=RuntimeDirectory=ramshackle-admin \
        --property=WorkingDirectory=/var/lib/ramshackle \
        ${
          lib.optionalString (cfg.environmentFile != null) "--property=EnvironmentFile=${cfg.environmentFile}"
        } \
        ${
          lib.concatStringsSep " " (
            lib.mapAttrsToList (name: value: lib.escapeShellArg "--setenv=${name}=${value}") adminEnvironment
          )
        } \
        -- ${withSecrets} ${cfg.package}/bin/ramshackle ${command} ${args}
    '';

  rootExample = "'Ramshackle.Release.create_root(\"you@example.com\", public_url: \"https://ramshackle.example.com\")'";

  adminCommands = [
    (releaseCommand {
      name = "ramshackle-eval";
      usage = rootExample;
      command = "eval";
      args = ''"$1"'';
      systemdRunFlags = "--pipe";
    })
    (releaseCommand {
      name = "ramshackle-rpc";
      usage = "'IO.inspect(node())'";
      command = "rpc";
      args = ''"$1"'';
      systemdRunFlags = "--pipe";
    })
    (releaseCommand {
      name = "ramshackle-remote";
      usage = null;
      command = "remote";
      args = "";
      systemdRunFlags = "--pty";
    })
  ];
in
{
  # These moved into the database, where root manages them in the admin pages.
  imports =
    map
      (
        path:
        lib.mkRemovedOptionModule
          (
            [
              "services"
              "ramshackle"
            ]
            ++ path
          )
          ''
            Ramshackle now keeps this in its database: sign in as root and set it in the
            admin pages. The service only needs services.ramshackle.masterKeyFile.
          ''
      )
      [
        [ "host" ]
        [ "secretKeyBaseFile" ]
        [ "tokenSigningSecretFile" ]
        [
          "github"
          "clientId"
        ]
        [
          "github"
          "clientSecretFile"
        ]
        [
          "github"
          "redirectUri"
        ]
        [ "mailFrom" ]
      ];

  options.services.ramshackle = {
    enable = mkEnableOption "the Ramshackle server";

    package = mkOption {
      type = types.package;
      default = self.packages.${pkgs.stdenv.hostPlatform.system}.ramshackle;
      defaultText = literalExpression "ramshackle.packages.\${pkgs.stdenv.hostPlatform.system}.ramshackle";
      description = "The Ramshackle release to run.";
    };

    port = mkOption {
      type = types.port;
      default = 4000;
      description = "Port the HTTP server listens on, on all interfaces.";
    };

    openFirewall = mkOption {
      type = types.bool;
      default = false;
      description = "Whether to open {option}`services.ramshackle.port` in the firewall.";
    };

    masterKeyFile = mkOption {
      type = secretPath;
      example = "/run/secrets/ramshackle-master-key";
      description = ''
        File holding the master key: 32 random bytes, Base64-encoded, from
        `openssl rand -base64 32`. It encrypts every secret Ramshackle stores
        in its database, including the ones it generates on first boot, so
        back it up apart from the database: without it they cannot be read.
        It is passed to the service as a systemd credential, so it can be
        readable by root only, and it never enters the Nix store.

        Everything else (the public URL, mail, GitHub sign-in, tenants) is
        configured by root in the admin pages. Onboard root with
        `ramshackle-eval`, which this module installs:

            ramshackle-eval 'Ramshackle.Release.create_root("you@example.com", public_url: "https://ramshackle.example.com")'

        `ramshackle-rpc EXPR` and `ramshackle-remote` reach the running server
        over Erlang distribution on 127.0.0.1.
      '';
    };

    environmentFile = mkOption {
      type = types.nullOr types.path;
      default = null;
      example = "/run/secrets/ramshackle.env";
      description = ''
        Optional file of `NAME=value` lines added to the service environment.
        Use it for secrets such as a `DATABASE_URL` that holds a password.
      '';
    };

    environment = mkOption {
      type = types.attrsOf types.str;
      default = { };
      example = {
        ECTO_IPV6 = "true";
      };
      description = ''
        Extra environment variables for the server. They end up in the Nix
        store, so do not put secrets here; use
        {option}`services.ramshackle.environmentFile` instead.
      '';
    };

    database = {
      createLocally = mkOption {
        type = types.bool;
        default = true;
        description = ''
          Whether to run PostgreSQL on this machine and create the database
          and role for Ramshackle. The server connects over the Unix socket
          with peer authentication, so no password is needed.
        '';
      };

      name = mkOption {
        type = types.str;
        default = "ramshackle";
        description = "Name of the PostgreSQL database.";
      };

      user = mkOption {
        type = types.str;
        default = "ramshackle";
        description = ''
          PostgreSQL role and system user the server runs as. With
          {option}`services.ramshackle.database.createLocally`, the role owns
          the database.
        '';
      };

      url = mkOption {
        type = types.nullOr types.str;
        default = if cfg.database.createLocally then localDatabaseUrl else null;
        defaultText = literalExpression ''
          if config.services.ramshackle.database.createLocally
          then "ecto://''${user}@localhost/''${name}?socket_dir=/run/postgresql"
          else null
        '';
        description = ''
          Ecto URL of the database. Set it to `null` and put `DATABASE_URL`
          in {option}`services.ramshackle.environmentFile` when the URL holds
          a password.
        '';
      };

      poolSize = mkOption {
        type = types.ints.positive;
        default = 10;
        description = "Number of database connections in the pool.";
      };
    };
  };

  config = mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.database.url != null || cfg.environmentFile != null;
        message = "services.ramshackle needs database.url, or a DATABASE_URL in environmentFile.";
      }
      {
        assertion =
          cfg.database.createLocally -> lib.versionAtLeast config.services.postgresql.package.version "17";
        message = "services.ramshackle needs PostgreSQL 17 or later. Set services.postgresql.package = pkgs.postgresql_17 (migrate any existing cluster first).";
      }
    ];

    users.users.${cfg.database.user} = {
      isSystemUser = true;
      group = cfg.database.user;
      description = "Ramshackle server";
    };
    users.groups.${cfg.database.user} = { };

    services.postgresql = mkIf cfg.database.createLocally {
      enable = true;
      ensureDatabases = [ cfg.database.name ];
      ensureUsers = [
        {
          name = cfg.database.user;
          ensureDBOwnership = true;
        }
      ];
    };

    networking.firewall.allowedTCPPorts = optional cfg.openFirewall cfg.port;

    environment.systemPackages = adminCommands;

    systemd.services.ramshackle = {
      description = "Ramshackle server";
      wantedBy = [ "multi-user.target" ];
      wants = [ "network-online.target" ];
      after = [ "network-online.target" ] ++ optional cfg.database.createLocally "postgresql.target";
      requires = optional cfg.database.createLocally "postgresql.target";

      inherit environment;

      serviceConfig = {
        Type = "exec";
        User = cfg.database.user;
        Group = cfg.database.user;
        ExecStartPre = "${withSecrets} ${cfg.package}/bin/migrate";
        ExecStart = "${withSecrets} ${cfg.package}/bin/server";
        ExecStop = "${withSecrets} ${cfg.package}/bin/ramshackle stop";
        EnvironmentFile = mkIf (cfg.environmentFile != null) cfg.environmentFile;
        LoadCredential = [ "master_key:${cfg.masterKeyFile}" ];
        Restart = "on-failure";
        RestartSec = 5;

        StateDirectory = "ramshackle";
        StateDirectoryMode = "0750";
        RuntimeDirectory = "ramshackle";
        RuntimeDirectoryMode = "0750";
        WorkingDirectory = "/var/lib/ramshackle";

        # Hardening. The BEAM JIT needs writable and executable memory, so
        # MemoryDenyWriteExecute stays off.
        CapabilityBoundingSet = "";
        DevicePolicy = "closed";
        LockPersonality = true;
        NoNewPrivileges = true;
        PrivateDevices = true;
        PrivateTmp = true;
        PrivateUsers = true;
        ProtectClock = true;
        ProtectControlGroups = true;
        ProtectHome = true;
        ProtectHostname = true;
        ProtectKernelLogs = true;
        ProtectKernelModules = true;
        ProtectKernelTunables = true;
        ProtectProc = "invisible";
        ProcSubset = "pid";
        ProtectSystem = "strict";
        RemoveIPC = true;
        RestrictAddressFamilies = [
          "AF_INET"
          "AF_INET6"
          "AF_UNIX"
        ];
        RestrictNamespaces = true;
        RestrictRealtime = true;
        RestrictSUIDSGID = true;
        SystemCallArchitectures = "native";
        SystemCallFilter = [
          "@system-service"
          "~@privileged"
        ];
        UMask = "0077";
      };
    };
  };
}
