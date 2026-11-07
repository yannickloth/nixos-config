# PostgreSQL 18.6 — fleet-wide database server.
#
# Data directory lives on /data/postgres/18 on every laptop. laptop-hera and
# laptop-p16 mount /data via LUKS+btrfs so the database is encrypted on disk;
# laptop-xps creates /data as a plain root-FS directory, so its copy is not
# encrypted (no second drive on that machine).
#
# Authentication:
#   - Unix socket: peer auth (psql/pgcli as nicky, no password needed)
#   - TCP localhost (127.0.0.1): scram-sha-256 using the secret
#     /run/agenix/pg-nicky-password — set by the oneshot service below.
#     This is what IDEs (Datagrip, JetBrains IDEs) use.
#
# Mirrors services/nix-serve.nix pattern: values are set directly in the
# module body (not inside mkIf), relying on the nixpkgs postgresql module's
# internal mkIf to activate the service when enable = true.
{ config, lib, pkgs, ... }:

with lib;

{
  # Direct configuration of the nixpkgs postgresql module — enable flag and
  # all service parameters are set here, unconditionally.  The nixpkgs module
  # wraps the actual activation in its own `mkIf cfg.enable` so this is safe
  # and avoids any option-evaluation recursion.
  services.postgresql = {
    enable = true;
    package = pkgs.postgresql_18;                    # 18.6, latest in pinned nixpkgs
    dataDir   = "/data/postgres/18";                  # non-default → module sets ReadWritePaths

    # Default role and database for nicky. Peer auth via Unix socket gives
    # nicky full access to the "nicky" database with no password.
    ensureDatabases = [ "nicky" ];
    ensureUsers = [
      { name = "nicky"; ensureDBOwnership = true; }
    ];

    # Allow TCP connections on localhost (IDEs like Datagrip).
    enableTCPIP = true;

    # Peer auth over Unix socket + scram-sha-256 over localhost TCP.
    # The default pg_hba already has:
    #   local all all     peer
    #   host  all all 127.0.0.1/32 md5
    # We replace md5 with scram-sha-256 for security (md5 is deprecated).
    authentication = ''
      local   all all   peer
      host    all all 127.0.0.1/32 scram-sha-256
    '';
  };

  # --- first-boot password provisioning ---

  # Runs once after postgresql-setup (which creates the nicky role via
  # ensureUsers).  Idempotent: ALTER ROLE succeeds if the role exists,
  # silently does nothing if it doesn't yet (first boot race with the
  # oneshot service ordering).  Reads the password from the agenix-decrypted
  # file and pipes it as a parameter to psql.
  systemd.services.postgresql-set-nicky-password = {
    description = "Set PostgreSQL nicky role password from agenix secret";
    after = [ "postgresql-setup.service" ];
    wants   = [ "postgresql-setup.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      User   = "postgres";
      Group  = "postgres";
      Type   = "oneshot";
      RemainAfterExit = true;
      ExecStart = ''
        ${config.services.postgresql.finalPackage}/bin/psql -v pw="'$(cat /run/agenix/pg-nicky-password)'" \
          -c "DO \$\$ BEGIN EXECUTE 'ALTER ROLE nicky PASSWORD :' || 'pw' EXCEPTION WHEN undefined_object THEN NULL; END \$\$;"
      '';
      SystemCallArchitectures = "native";
      ProtectHome    = true;
      ProtectSystem  = "strict";
      PrivateTmp     = true;
      ReadWritePaths = config.services.postgresql.dataDir;
    };
    path = [ config.services.postgresql.finalPackage pkgs.coreutils ];
  };
}
