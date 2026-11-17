# PostgreSQL 18 — fleet-wide database server.
#
# Data directory lives on /data/postgres/18 on every host. laptop-hera and
# laptop-p16 mount /data via LUKS+btrfs so the database is encrypted on disk;
# the other hosts create /data as a plain root-FS directory, so their copy is
# not encrypted (no second drive on those machines).
#
# Authentication:
#   - Unix socket: peer auth (psql/pgcli as nicky, no password needed)
#   - TCP localhost (127.0.0.1): scram-sha-256 using the secret
#     /run/agenix/pg-nicky-password — applied by the oneshot service below.
#     This is what IDEs (Datagrip, JetBrains IDEs) use.
#
# Mirrors services/nix-serve.nix pattern: values are set directly in the
# module body (not inside mkIf), relying on the nixpkgs postgresql module's
# internal mkIf to activate the service when enable = true.
{ config, lib, pkgs, ... }:

let
  cfg = config.services.postgresql;

  # The agenix-decrypted password (root:postgres 0640, see services/secrets.nix),
  # readable by the postgres user both units run as.
  passwordFile = "/run/agenix/pg-nicky-password";

  # Applies the password to the nicky role. Run both by the oneshot below and
  # at the end of postgresql-setup (which is exactly when ensureUsers has
  # created the role, so the two units cannot race).
  #
  # psql only expands `:'pw'` variables in a script fed through -f/stdin, NOT in
  # `-c` (verified: -c sends the statement verbatim and dies on the colon). So
  # the ALTER arrives as a one-line .sql file. psql then quotes the value as a
  # SQL literal itself, which makes any password safe: no shell quoting, no SQL
  # injection, and the secret never touches the process list (-c with the
  # literal would show it in `ps`).
  #
  # A newline or a ':' in the secret would silently corrupt nicky's ~/.pgpass
  # (users/nicky/nicky-hm.nix writes it line-based), so it is rejected up
  # front instead of handing clients a truncated password.
  setPassword = pkgs.writeShellScript "postgresql-set-nicky-password" ''
    set -euo pipefail

    if [ ! -r ${lib.escapeShellArg passwordFile} ]; then
      echo "postgresql: ${passwordFile} is missing or unreadable - is agenix activated?" >&2
      exit 1
    fi
    if head -c -1 ${lib.escapeShellArg passwordFile} | grep -q '[:[:cntrl:]]'; then
      echo "postgresql: ${passwordFile} must be one line without ':' (pgpass format)" >&2
      exit 1
    fi

    exec ${cfg.finalPackage}/bin/psql -X -v ON_ERROR_STOP=1 -d postgres \
      -v pw="$(cat ${lib.escapeShellArg passwordFile})" \
      -f ${../packages/postgresql/alter-role-password.sql}
  '';
in
{
  # Direct configuration of the nixpkgs postgresql module — enable flag and
  # all service parameters are set here, unconditionally. The nixpkgs module
  # wraps the actual activation in its own `mkIf cfg.enable` so this is safe
  # and avoids any option-evaluation recursion.
  services.postgresql = {
    enable = true;
    package = pkgs.postgresql_18;                     # 18.6, latest in pinned nixpkgs
    dataDir = "/data/postgres/18";                    # non-default → module sets ReadWritePaths

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

  # --- data directory ---

  # nixpkgs provisions a StateDirectory only for its DEFAULT data dir; with a
  # custom `dataDir` the path is the caller's responsibility. The unit still
  # gets RequiresMountsFor=/data/postgres/18 and ReadWritePaths=/data/postgres/18,
  # so when the path is missing the start dies in 226/NAMESPACE before initdb
  # (which runs in preStart, i.e. after the mount namespace is set up) can
  # create it. Create the full path here, owned by postgres, 0700 as initdb
  # wants it; tmpfiles runs before postgresql.service.
  systemd.tmpfiles.rules = [
    "d /data/postgres/18 0700 postgres postgres -"
  ];

  # --- password provisioning ---

  systemd.services.postgresql-set-nicky-password = {
    description = "Set PostgreSQL nicky role password from agenix secret";
    after = [ "postgresql-setup.service" "agenix.service" ];
    wants = [ "postgresql-setup.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      User = "postgres";
      Group = "postgres";
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = setPassword;
      SystemCallArchitectures = "native";
      ProtectHome = true;
      ProtectSystem = "strict";
      PrivateTmp = true;
      # The secret lives in /run/agenix, outside what ProtectSystem covers.
      ReadOnlyPaths = [ "/run/agenix" ];
    };
    path = [ config.services.postgresql.finalPackage pkgs.coreutils pkgs.gnugrep ];
  };

  # The race-proof half. postgresql-setup is what runs ensureUsers, so its
  # postStart is the first moment the role is guaranteed to exist - the oneshot
  # above may already have fired (and failed) against a fresh cluster.
  # mkAfter keeps nixpkgs' own postStart (the .first_startup cleanup) first.
  systemd.services.postgresql-setup.postStart = lib.mkAfter "${setPassword}";
}
