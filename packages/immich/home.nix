# home-manager wrapper that runs the Immich server stack (server + AI
# machine-learning + PostgreSQL/vectorchord + Redis) as rootless Podman
# containers under a systemd user service.
#
# Why containers: home-manager has no Immich module, and Immich needs
# PostgreSQL with the vectorchord extension, Redis and the ML service running
# together — reproducing that as nixpkgs user services is far more fragile than
# the official images the upstream project ships. This wraps upstream's
# docker-compose.yml (same images, same layout), so an image/tag bump is a
# one-line change here (immich.version).
#
#   imports = [ ../../packages/immich/home.nix ];
#   immich.enable = true;
#
# A server is a single instance and both parents share laptop-p16, so the stack
# is meant to run under ONE account (nicky; see users/nicky/nicky-hm.nix).
# aeiuno reaches the same instance from a browser (http://localhost:2283 on p16,
# or the Tailscale IP from another device).
#
# Host prerequisites (home-manager cannot set these on a non-NixOS host; the
# activation warns if they are missing):
#   sudo usermod --add-subuids 100000-165535 --add-subgids 100000-165535 $USER
#   sudo loginctl enable-linger $USER
# On CachyOS the firewall is host-managed; publishing ports in the compose
# exposes the server on both the LAN and the Tailscale overlay.
{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
let
  cfg = config.immich;

  configDir = "${config.xdg.configHome}/immich";
  stateDir = "${config.home.homeDirectory}/.local/share/immich";

  # Upstream's compose, with the two host paths baked in (Nix interpolation)
  # and the image tag pinned via cfg.version. ${DB_*} are escaped so
  # podman-compose substitutes them from the generated .env at runtime.
  composeFile = pkgs.writeText "immich-docker-compose.yml" ''
    name: immich

    services:
      immich-server:
        container_name: immich_server
        image: ghcr.io/immich-app/immich-server:${cfg.version}
        volumes:
          - ${cfg.mediaLocation}:/data
          - /etc/localtime:/etc/localtime:ro
        env_file:
          - .env
        ports:
          - '${toString cfg.port}:2283'
        depends_on:
          - redis
          - database
        restart: always
        healthcheck:
          disable: false

      immich-machine-learning:
        container_name: immich_machine_learning
        # Append -cuda / -openvino / -rocm to the tag for accelerated inference;
        # the CPU image is the simple default. See
        # https://docs.immich.app/features/ml-hardware-acceleration
        image: ghcr.io/immich-app/immich-machine-learning:${cfg.version}
        volumes:
          - model-cache:/cache
        env_file:
          - .env
        restart: always
        healthcheck:
          disable: false

      redis:
        container_name: immich_redis
        image: docker.io/valkey/valkey:9@sha256:c123e3715db63d06d4ad6964884037aa0d5d4d703939b9929954112889708e1d
        restart: always

      database:
        container_name: immich_postgres
        image: ghcr.io/immich-app/postgres:14-vectorchord0.4.3-pgvectors0.2.0@sha256:bcf63357191b76a916ae5eb93464d65c07511da41e3bf7a8416db519b40b1c23
        environment:
          POSTGRES_PASSWORD: ''${DB_PASSWORD}
          POSTGRES_USER: ''${DB_USERNAME}
          POSTGRES_DB: ''${DB_DATABASE_NAME}
          POSTGRES_INITDB_ARGS: '--data-checksums'
        volumes:
          - ${cfg.databaseLocation}:/var/lib/postgresql/data
        shm_size: 128mb
        restart: always
        healthcheck:
          disable: false

    volumes:
      model-cache:
  '';

  # podman-compose shells out to podman, which needs its rootless runtime and
  # network helpers; on a non-NixOS host the setuid newuidmap/newgidmap come
  # from the host's shadow package. Keep podman's helpers on the unit PATH and
  # append the host bin dirs so those setuid helpers are found (setuid cannot
  # live in the Nix store).
  unitPath = lib.makeBinPath [
    pkgs.podman
    pkgs.podman-compose
    pkgs.crun
    pkgs.conmon
    pkgs.netavark
    pkgs.aardvark-dns
    pkgs.passt
    pkgs.slirp4netns
    pkgs.fuse-overlayfs
    pkgs.bash
    pkgs.coreutils
  ];

  # podman-compose 1.x has no --project-directory flag (it would be parsed as
  # the subcommand); the project directory is the unit's WorkingDirectory, and
  # -p names the project so containers/volumes are stable across restarts.
  compose = "${pkgs.podman-compose}/bin/podman-compose -p immich --file ${configDir}/docker-compose.yml";
in
{
  options.immich = {
    enable = mkEnableOption "the Immich server stack (rootless Podman: server + machine-learning + postgres/vectorchord + redis)";

    version = mkOption {
      type = types.str;
      default = "release";
      example = "v3";
      description = ''
        Image tag for the immich-server and immich-machine-learning images
        (`release` tracks the latest stable release; pin e.g. `v3` to a major).
      '';
    };

    port = mkOption {
      type = types.port;
      default = 2283;
      description = "Host port the Immich web UI/server is published on (container port 2283).";
    };

    mediaLocation = mkOption {
      type = types.path;
      default = "${stateDir}/library";
      defaultText = literalExpression ''"''${config.home.homeDirectory}/.local/share/immich/library"'';
      description = ''
        Where uploaded photos/videos are stored (mounted at /data in the
        server container). Created by activation if it does not exist. Keep it
        off a Syncthing-replicated path: Immich is the source of truth here.
      '';
    };

    databaseLocation = mkOption {
      type = types.path;
      default = "${stateDir}/postgres";
      defaultText = literalExpression ''"''${config.home.homeDirectory}/.local/share/immich/postgres"'';
      description = "Where the PostgreSQL data directory is stored. Must be local storage, not a network share.";
    };

    databasePasswordFile = mkOption {
      type = types.nullOr types.path;
      default = null;
      description = ''
        File containing the PostgreSQL password (its entire contents, trailing
        newline stripped). When null (the default) a random password is
        generated into `~/.config/immich/.env` on first activation and kept
        there — it is never written to the Nix store.
      '';
    };
  };

  config = mkIf cfg.enable {
    assertions = [
      {
        assertion = !(lib.hasPrefix "${config.home.homeDirectory}/sync" (toString cfg.mediaLocation));
        message = "immich.mediaLocation is under ~/sync: Immich is the source of truth and must not be Syncthing-replicated.";
      }
    ];

    home.packages = with pkgs; [
      podman
      podman-compose
      # Rootless runtime + networking helpers (podman 5: netavark/aardvark-dns
      # for rootless CNI-less networking, pasta/slirp4netns as the network
      # backend, crun/conmon as the runtime, fuse-overlayfs for the store).
      crun
      conmon
      netavark
      aardvark-dns
      passt
      slirp4netns
      fuse-overlayfs
    ];

    home.file.".config/immich/docker-compose.yml".source = composeFile;

    # One-time provisioning: media/db dirs, and a per-install random DB password
    # in .env (written here rather than via home.file so it stays out of the
    # Nix store). Idempotent: the file is only created if absent.
    home.activation.immichProvision = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      $DRY_RUN_CMD ${pkgs.coreutils}/bin/mkdir -p "${cfg.mediaLocation}" "${cfg.databaseLocation}" "${configDir}"

      env_file="${configDir}/.env"
      if [ ! -f "$env_file" ]; then
        create_env() {
          local db_password
          if [ -n "${toString cfg.databasePasswordFile}" ]; then
            db_password="$(${pkgs.coreutils}/bin/cat "${toString cfg.databasePasswordFile}")"
          else
            db_password="$(${pkgs.coreutils}/bin/dd if=/dev/urandom bs=1 count=64 2>/dev/null \
              | ${pkgs.coreutils}/bin/base64 \
              | ${pkgs.coreutils}/bin/tr -dc 'A-Za-z0-9' \
              | ${pkgs.coreutils}/bin/cut -c1-40)"
          fi
          umask 077
          ${pkgs.coreutils}/bin/printf 'DB_PASSWORD=%s\nDB_USERNAME=postgres\nDB_DATABASE_NAME=immich\n' "$db_password" > "$env_file"
        }
        $DRY_RUN_CMD create_env
      fi
    '';

    # The server must outlive logout (lingering), and rootless podman needs a
    # subuid/subgid range for this user. Both are system-level and cannot be set
    # from home-manager on a non-NixOS host, so warn with the exact commands.
    home.activation.immichHostRequirements = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      if ! ${pkgs.systemd}/bin/loginctl show-user "$USER" -p Linger 2>/dev/null | ${pkgs.gnugrep}/bin/grep -q 'Linger=yes'; then
        if sudo -n true 2>/dev/null; then
          $DRY_RUN_CMD sudo ${pkgs.systemd}/bin/loginctl enable-linger "$USER" || true
        else
          echo "immich: the server needs lingering; run once: sudo loginctl enable-linger $USER" >&2
        fi
      fi

      if ! ${pkgs.gnugrep}/bin/grep -q "^$USER:" /etc/subuid 2>/dev/null; then
        echo "immich: rootless podman needs a subuid range; run once: sudo usermod --add-subuids 100000-165535 --add-subgids 100000-165535 $USER" >&2
      fi
    '';

    systemd.user.services.immich = {
      Unit = {
        Description = "Immich server stack (rootless podman-compose)";
        After = [ "network-online.target" ];
        Wants = [ "network-online.target" ];
        # Cap restarts so a persistent failure (e.g. missing subuid range)
        # cannot spin the unit every RestartSec forever.
        StartLimitIntervalSec = 300;
        StartLimitBurst = 5;
      };
      Install = {
        WantedBy = [ "default.target" ];
      };
      Service = {
        Type = "oneshot";
        RemainAfterExit = true;
        WorkingDirectory = configDir;
        # Host bin dirs appended so podman finds /usr/bin/newuidmap (shadow).
        Environment = [
          "PATH=${unitPath}:/run/wrappers/bin:/usr/local/bin:/usr/bin:/bin"
        ];
        ExecStart = "${compose} up -d";
        ExecStop = "${compose} down";
        # Generous: the first start pulls several GB of images.
        TimeoutStartSec = "30min";
        Restart = "on-failure";
        RestartSec = "10s";
      };
    };
  };
}
