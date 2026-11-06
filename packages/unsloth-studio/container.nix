# Unsloth Studio as an OCI container (backend = "container").
#
# Why this exists next to the native path in ./home.nix: Studio is built for a
# normal Linux userland. install.sh writes a venv into $HOME, rebuilds
# llama.cpp in place, swaps audio/image engines and self-updates; on CachyOS
# that is exactly what upstream tests, on NixOS it is a fight against the
# stubs (see the header of ./home.nix for the two times it broke). The upstream
# image (docker/unsloth/unsloth, Dockerfile.studio) carries that userland —
# python, torch, CUDA 12.8, the baked llama.cpp and the audio/image engines —
# so the host only has to provide podman, the GPU device and a port.
#
# Rootless podman under the owning user, started by a systemd *user* unit, is
# the whole trick: `users.users.<owner>.linger` (or the CachyOS equivalent,
# `loginctl enable-linger`) starts the user manager at boot, so the instance
# runs whoever is logged in. The port is published on 127.0.0.1 only; every
# local user reaches it there, and nothing is exposed to the LAN. Studio binds
# 0.0.0.0 INSIDE the container on purpose (docker/studio_run.sh: "the container
# is the boundary"), so never add --network=host.
#
# Updates need no nix switch. The image reference lives in imageFile, which an
# activation seeds once and never overwrites; the weekly timer (or
# `systemctl --user start unsloth-studio-update`) pulls whatever that file
# names and cycles the container. To pin, roll back or move to a nightly, edit
# the file and start the updater. In-place updates inside the container
# (`podman exec unsloth-studio unsloth-studio-update`) work but live in the
# writable layer and die when the container is recreated — upstream says so in
# docker/unsloth_studio_update.sh; the pull is the lasting path.
#
# Content is split between the podman named volume (Studio's accounts, chats,
# exports and runs under /opt/unsloth-studio) and dataDir on the host (HF cache
# and the /workspace/host drop). The named volume is required: Studio needs
# symlinks there, which a host folder may refuse.
{ config, lib, pkgs, ... }:
with lib;
let
  cfg = config.unsloth-studio;
  home = config.home.homeDirectory;
  containerName = "unsloth-studio";

  # The run line. Kept as a file in ~/.local/bin (like the native launcher) so
  # `podman run` can be read and copy-pasted when debugging.
  runScript = pkgs.writeShellScript "unsloth-studio-container" ''
    set -eu
    image_file=${escapeShellArg cfg.imageFile}
    if [ ! -r "$image_file" ]; then
      echo "unsloth-studio: missing image file $image_file" >&2
      exit 1
    fi
    image="$(cat "$image_file")"

    # dataDir lives under /data: a separate LUKS+btrfs volume on laptop-p16
    # (see hosts/laptop-p16/cachyos/automount-data.sh) and laptop-hera, a
    # root-disk directory on laptop-xps. Touching it first trips the p16
    # automount unit when it is not mounted yet, and fails here with a
    # readable reason instead of deep inside podman as "permission denied".
    if ! ${pkgs.coreutils}/bin/mkdir -p ${escapeShellArg cfg.dataDir}/hf ${escapeShellArg cfg.dataDir}/host 2>/dev/null; then
      echo "unsloth-studio: cannot create ${cfg.dataDir} - is /data unlocked and mounted?" >&2
      exit 1
    fi

    # UNSLOTH_STUDIO_PASSWORD from the env file keeps the first boot from
    # generating a password and shutting itself down after the bootstrap
    # timeout. Optional: without the file the credential lands in the journal.
    env_args=()
    ${optionalString (cfg.environmentFile != null) ''
      if [ -r ${escapeShellArg cfg.environmentFile} ]; then
        env_args=(--env-file ${escapeShellArg cfg.environmentFile})
      fi
    ''}

    # The image's entrypoint requires Turing or newer (sm_75) when a GPU is
    # visible, and exits 1 below that. On a host without a supported card leave
    # gpu off: the image then starts in CPU mode (UNSLOTH_IMAGE_ALLOW_CPU=1).
    gpu_args=()
    ${optionalString cfg.gpu ''gpu_args=(--device nvidia.com/gpu=all)''}

    # A container left behind by a podman that systemd killed (the stop timeout)
    # would make every subsequent `run` fail with "name already in use" and the
    # unit would restart-loop. --ignore keeps the first start clean.
    ${cfg.podman} rm -f --ignore ${containerName} >/dev/null 2>&1 || true

    # Detached on purpose. A foreground `podman run` keeps the CLI alive as the
    # unit's main process, and that CLI holds libpod's storage lock for the whole
    # container lifetime: every other podman command (`podman ps`, `podman info`,
    # Podman Desktop's socket) then blocks indefinitely. `podman wait` is the
    # blocker instead - it observes the container and takes no storage lock.
    net_args=()
    ${optionalString cfg.hostLoopback ''net_args=(--network=pasta:--map-host-loopback,169.254.1.2)''}

    ${cfg.podman} run -d --rm --name ${containerName} \
      "''${net_args[@]}" \
      "''${gpu_args[@]}" \
      --ipc=host \
      --ulimit memlock=-1 --ulimit stack=67108864 \
      -p 127.0.0.1:${toString cfg.port}:8000 \
      "''${env_args[@]}" \
      -v ${containerName}:/opt/unsloth-studio \
      -v ${escapeShellArg cfg.dataDir}/hf:/workspace/.cache/huggingface \
      -v ${escapeShellArg cfg.dataDir}/host:/workspace/host \
      "$image"

    # Blocks until the container exits, so systemd tracks liveness and
    # Restart=always still applies. ExecStop below stops the container itself.
    exec ${cfg.podman} wait ${containerName}
  '';

  updateScript = pkgs.writeShellScript "unsloth-studio-update" ''
    set -eu
    image_file=${escapeShellArg cfg.imageFile}
    if [ ! -r "$image_file" ]; then
      echo "unsloth-studio-update: missing image file $image_file" >&2
      exit 1
    fi
    image="$(cat "$image_file")"
    if [ -z "$image" ]; then
      echo "unsloth-studio-update: $image_file is empty" >&2
      exit 1
    fi
    ${cfg.podman} pull "$image"
    # The run unit is Restart=always, so killing the container brings it back on
    # the pulled image. No systemctl: the container is the unit's own child, and
    # the client binary in the store need not match the host's systemd.
    ${cfg.podman} kill ${containerName} 2>/dev/null || true
    # Old layers behind the same tag are dangling after a pull; keep a week.
    ${cfg.podman} image prune -f --filter until=168h >/dev/null 2>&1 || true
  '';
in
{
  options.unsloth-studio = {
    backend = mkOption {
      type = types.enum [ "native" "container" ];
      default = "native";
      description = ''
        "native" runs upstream's install.sh into $HOME (see ./home.nix).
        "container" runs the official image under rootless podman, which is the
        supported userland for Studio. The two are mutually exclusive: both
        own the same port.
      '';
    };

    image = mkOption {
      type = types.str;
      default = "docker.io/unsloth/unsloth:studio";
      description = ''
        Image reference seeded into imageFile on first activation. `:studio` is
        the rolling tag (equal to the newest nightly); `:v0.1.915-beta` and the
        nightly-YYYY.MM.DD tags pin a release, `:core` is the smaller image for
        --user runs. After the seed the file wins, so changing this option does
        not redirect an existing install.
      '';
    };

    imageFile = mkOption {
      type = types.str;
      default = "${home}/.local/share/unsloth-studio/image";
      description = ''
        Mutable record of the image to run. Seeded once by an activation and
        never overwritten, so a tag bump or rollback needs no home-manager
        switch: edit the file, then start unsloth-studio-update.
      '';
    };

    dataDir = mkOption {
      type = types.str;
      default = "${home}/.local/share/unsloth-studio/data";
      description = ''
        Host directory for the bind mounts (HF cache at dataDir/hf, the
        /workspace/host drop at dataDir/host). Put it on a filesystem with room
        for models: the image itself is ~10 GB and each GGUF is several more.
        Studio's own DB and exports stay in the podman named volume.
      '';
    };

    environmentFile = mkOption {
      type = types.nullOr types.str;
      default = "${home}/.config/unsloth-studio.env";
      description = ''
        Optional env file passed with --env-file. Set
        UNSLOTH_STUDIO_PASSWORD here so the first boot does not generate a
        password and shut Studio down after the bootstrap timeout
        (UNSLOTH_STUDIO_BOOTSTRAP_TIMEOUT, 3600 s). Other upstream variables
        (HF_TOKEN, JUPYTER_PASSWORD, ...) go here too.
      '';
    };

    hostLoopback = mkOption {
      type = types.bool;
      default = true;
      description = ''
        Map the host's loopback into the container at 169.254.1.2
        (pasta --map-host-loopback), so a host service bound to 127.0.0.1 is
        reachable as http://host.containers.internal:<port>. Needed for the
        Strata provider: Strata listens on 127.0.0.1:8080 by design and a
        rootless container cannot otherwise reach it. Requires rootless podman
        with pasta and a passt that knows --map-host-loopback.
      '';
    };

    gpu = mkOption {
      type = types.bool;
      default = true;
      description = ''
        Pass the NVIDIA GPU through CDI (--device nvidia.com/gpu=all). Requires
        nvidia-container-toolkit on the host and a generated CDI spec. Turn it
        off where the card is below the image's sm_75 floor (Pascal and older):
        with no GPU visible the image starts in CPU mode instead of exiting.
      '';
    };

    podman = mkOption {
      type = types.str;
      default = "${pkgs.podman}/bin/podman";
      description = ''
        podman binary the unit runs. The nixpkgs build is the default so the
        module evaluates anywhere. On a distro host (CachyOS) point this at the
        distro binary — /usr/bin/podman — so the service uses the same runtime,
        storage and CDI setup as the `podman` the user runs by hand: a second
        podman implementation would bring its own conmon/netavark paths.
      '';
    };

    podmanStorageRoot = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = ''
        When set, writes ~/.config/containers/storage.conf with this graphroot.
        Needed where the home filesystem cannot hold the image (the default is
        ~/.local/share/containers). Changing it orphans images pulled before;
        re-pull them.

        This is a user-wide setting, not a container one: every podman command
        the user runs reads it. Point it at a filesystem that is present at
        boot — if the path is missing, podman itself is unusable, not just this
        unit. On laptop-p16 that means the /data automount
        (hosts/laptop-p16/cachyos/automount-data.sh) must be installed.
      '';
    };
  };

  config = mkIf (cfg.enable && cfg.backend == "container") {
    # Seed the image file once. A switch must never reset it: that file is the
    # update channel.
    home.activation.unslothStudioImage =
      lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        $DRY_RUN_CMD ${pkgs.coreutils}/bin/mkdir -p ${escapeShellArg (dirOf cfg.imageFile)}
        if [ ! -e ${escapeShellArg cfg.imageFile} ]; then
          printf '%s\n' ${escapeShellArg cfg.image} > ${escapeShellArg cfg.imageFile}
        fi
      '';

    xdg.configFile = mkIf (cfg.podmanStorageRoot != null) {
      "containers/storage.conf" = {
        # Owned by this module: overwrite a hand-written file (podman is useless
        # with the wrong graphroot) instead of leaving the old one in place.
        force = true;
        text = ''
          [storage]
          driver = "overlay"
          graphroot = "${cfg.podmanStorageRoot}"
        '';
      };
    };

    home.file.".local/bin/unsloth-studio-container.sh" = {
      executable = true;
      source = runScript;
    };

    systemd.user.services.unsloth-studio = {
      Unit = {
        Description = "Unsloth Studio (container) - local inference web UI + API";
        After = [ "network-online.target" ];
      };
      Install = {
        WantedBy = [ "default.target" ];
      };
      Service = {
        Type = "simple";
        # Yield to the desktop while it is in use (packages/ai-slice.nix):
        # llama.cpp spawns one thread per core inside the container, so the
        # podman scope needs the same slice, weight and nice value as the
        # native unit in ./home.nix.
        Slice = "ai.slice";
        Nice = 10;
        IOSchedulingClass = "best-effort";
        IOSchedulingPriority = 7;
        ExecStart = "${home}/.local/bin/unsloth-studio-container.sh";
        # The run script detaches and waits, so stopping the unit must stop the
        # container explicitly (SIGTERM to `podman wait` alone leaves it running).
        ExecStop = "${cfg.podman} stop -t 150 ${containerName}";
        # Free the card before the container's llama.cpp allocates. The helper
        # is a host script (./handoff.nix), so it works whatever the backend;
        # only the in-load half of the handoff is native-only.
        ExecStartPre = optional cfg.strataGpuHandoff "-${home}/.local/bin/unsloth-studio-free-gpu.sh";
        Restart = "always";
        RestartSec = "15s";
        # The ExecStartPre handoff intentionally waits for Strata to drop the
        # 125B engine: its unload call blocks while a request runs, and the
        # helper then polls /health until the VRAM is back (up to
        # STRATA_UNLOAD_WAIT + 30 s for the call, then ~2 s × (wait + 60)/2).
        # At the user manager's 15 s default this pre-start was killed - the
        # unit failed and restarted forever whenever Strata was generating
        # (2026-11-05: Strata in a 391K-token turn, Studio stuck in
        # "activating (start-pre)"). 360 s covers the 120 s default wait with
        # margin; tune STRATA_UNLOAD_WAIT in the environment file to shorten
        # the gate.
        TimeoutStartSec = "360s";
        # podman needs a stop that outlasts supervisord's own studio stop wait.
        TimeoutStopSec = "180s";
      };
    };

    systemd.user.services.unsloth-studio-update = {
      Unit = {
        Description = "Update Unsloth Studio (pull image, cycle container)";
      };
      Service = {
        Type = "oneshot";
        ExecStart = updateScript;
        # A ~10 GB pull on a slow line; the timer runs it weekly.
        TimeoutStartSec = "2h";
      };
    };

    systemd.user.timers.unsloth-studio-update = {
      Unit = {
        Description = "Weekly Unsloth Studio image update";
      };
      Timer = {
        OnCalendar = "Mon *-*-* 09:00:00";
        Persistent = true;
        RandomizedDelaySec = "30min";
      };
      Install = {
        WantedBy = [ "timers.target" ];
      };
    };
  };
}
