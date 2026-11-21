# home-manager wrapper for the Strata package (see ./default.nix).
#
#   imports = [ ../../packages/strata/home.nix ];
#   strata.enable = true;   # gated on the host with the CUDA GPU (laptop-p16)
#
# Installs `strata` (Terminal CLI entry point + launcher), `strata-chat`,
# `strata-server`, and the desktop AppImage.
#
# The engine is installed as an upstream engine component (~/.local/share/strata/
# components/engine/0.1.63-linux-x86_64-cuda/) with a per-file SHA-256 manifest,
# built in the Nix store by engine.nix. The Terminal tree (setup.py, strata.py,
# serve/, strata_cli/, strata_control/, tools/, data/, requirements*.txt) is
# refreshed from the store on every `strata` invocation. Both `strata launch`
# (Terminal) and the desktop app install models through setup.py in CONTROL mode,
# writing `exe: "component:strata-engine"`.
#
# Upstream 0.2.17 changes:
# - Route-tail-skip is OFF by default (strata Control sets
#   STRATA_ROUTE_TAIL_SKIP=0 per start). Bench baseline delta expected.
# - Setup leaves 17 GB of RAM free (not 24): only affects non-fitting models
#   on PCs with <128 GB RAM. Our 125B is fully resident.
# - Engine 0.1.63, feed 129: no Nix involvement needed for the engine
#   (we build it in the store).
#
# `dataOnDataVolume = true` moves both the runtime tree and the data folder
# (~70-120 GB) to the /data volume, leaving symlinks in place so existing
# paths resolve unchanged.
{ config, lib, pkgs, ... }:
with lib;
let
  cfg = config.strata;
  # The desktop app: upstream's AppImage, both paths in the store. Only touched
  # when strata.desktop.enable is set (see the option below).
  desktop = pkgs.callPackage ./desktop.nix { };
in
{
  # The `ai.slice` both inference stacks run in (see ../ai-slice.nix). Imported
  # here, not from a user's config, so any host that enables either stack gets
  # the same resource budget.
  imports = [ ../ai-slice.nix ];

  options.strata = {
    enable = mkEnableOption "Strata (local Qwen3.8-Flash-Next 125B MoE inference, OpenAI/Anthropic API on localhost)";

    package = mkOption {
      type = types.package;
      default = pkgs.callPackage ./default.nix {
        # context is the only tuning value we keep in Nix (engine KV/window
        # capacity); every other engine knob is owned by `strata --setup` at
        # runtime.
        inherit (cfg) context vision visionEncoder;
        # CachyOS needs the /usr/lib/libcuda shim; NixOS uses the driver runpath
        # (set by the standalone CachyOS flake / left false on NixOS).
        inherit (config.commonHm) isCachyOS;
      };
      defaultText = literalExpression "pkgs.callPackage ./default.nix { inherit (config.strata) context vision visionEncoder; inherit (config.commonHm) isCachyOS; }";
      description = "The Strata package providing the engine and the setup/start wrappers.";
    };

    vision = mkOption {
      type = types.bool;
      default = false;
      description = ''
        Serve images by default: the wrapper passes `--vision yes` to setup
        (`--vision no` overrides it for one run) and strata-server preloads the
        engine instead of loading it lazily. Off by default: it drops throughput
        from ~35 to ~22 tok/s. Costs ~1.2 GB of VRAM for the encoder and a
        ~0.9 GB mmproj download on first setup. Implies `visionEncoder`.
      '';
    };

    visionEncoder = mkOption {
      type = types.bool;
      default = cfg.vision;
      defaultText = literalExpression "config.strata.vision";
      description = ''
        Build and ship the strata-vision image encoder, without deciding what
        setup does with it. With the binary installed, `strata --setup` asks the
        images question and both answers work (yes: CPU encoder on a 12 GB card,
        ~35 -> ~22 tok/s; no: text only). Costs only disk until images are used.
        Leave it false and the setup run is forced text-only, because the
        package has no encoder to enable.
      '';
    };

    desktop = {
      enable = mkEnableOption ''
        the Strata desktop app (upstream's Tauri AppImage, symlinked into
        ~/.local/opt with a desktop entry). It shares this package's models,
        packs and run configs, and it can either load a local model with its own
        bundled engine (copied into ~/.local/share/strata/components, ~1 GB, on
        first start) or talk to any OpenAI/Anthropic-compatible API through a
        saved connection - including this package's own server at
        http://127.0.0.1:8080/v1. NVIDIA CUDA 13 build: needs driver 580 or newer
      '';

      stopServerOnLaunch = mkOption {
        type = types.bool;
        default = false;
        description = ''
          Stop `strata.service` (and unsloth-studio) before the app
          starts. Off by default: as a front end the app can point at a running
          server or another API, and stopping it would break that connection.
          Turn it on only if you load a *local* model in the app - its own
          engine then needs the whole card, and only one owner can hold it.
          Started with the app, the stopped units are not restarted
          automatically; `systemctl --user start strata.service` brings the
          server back.
        '';
      };
    };

    context = mkOption {
      type = types.nullOr types.ints.positive;
      default = null;
      description = ''
        Engine KV/state capacity (`--max-context`). Null — this module does not
        enforce any context window: `strata --setup` probes the card and writes
        the optimal value into the run config. The package's default is also
        null (it leaves the window to `strata --setup`).
      '';
    };

    autoStart = mkOption {
      type = types.bool;
      default = true;
      description = ''
        Start `strata-server` at login. The server itself is light (no engine
        until a request); it is what lets Unsloth Studio reach the 125B on
        demand. false leaves the unit installed but stopped: start it with
        `systemctl --user start strata`.
      '';
    };

    idleUnloadSeconds = mkOption {
      type = types.ints.positive;
      default = 300;
      description = ''
        Seconds without a request after which `strata-server` unloads the
        engine (freeing ~55 GB of RAM and most of the GPU). The next request
        starts it again — measured ~27-30 s of weight loading into VRAM before
        decode can begin, so every idle gap longer than this value costs that
        stall. Raise it to keep the engine resident across longer pauses; the
        cost is holding the RAM and GPU while idle.
      '';
    };

    port = mkOption {
      type = types.port;
      default = 8080;
      description = "Port of the Strata API (bound per `strata.host`; the port Studio's Custom provider points at).";
    };

    host = mkOption {
      type = types.str;
      default = "127.0.0.1";
      description = ''
        Address the Strata API listens on (`STRATA_HOST`). Loopback by
        default: the server is for this machine's clients (Studio, opencode,
        the desktop app). Set it to 0.0.0.0 where the host firewall scopes
        the exposure, e.g. to reach the 125B from another inference host, a
        phone on the LAN or a tailnet peer. Note the server's Host-header
        check (DNS-rebinding protection): beyond loopback it answers to its
        own name and LAN addresses automatically, and IP-address Host headers
        always pass, but a MagicDNS name (`.bee-blues.ts.net`) needs an
        `allowedHosts` entry.
      '';
      example = "0.0.0.0";
    };

    minFreeVramMib = mkOption {
      type = types.ints.unsigned;
      default = 0;
      description = ''
        Refuse to start the engine unless this much VRAM is free (`--min-free-vram-mib`).
        On the shared A3000 this is the guard that keeps Strata from loading into a card
        Unsloth Studio's own model has already filled: the request answers 503 with a
        Retry-After instead of spilling to CPU or dying on a failed allocation. 0 leaves
        the check off (the engine tries anyway).
      '';
    };

    allowedHosts = mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = ''
        Extra `Host:` values the server accepts (`STRATA_ALLOWED_HOSTS`). Strata
        answers 403 to anything else as DNS-rebinding protection, so a client
        that reaches it under a name other than localhost must be listed here —
        e.g. `host.containers.internal` for the Unsloth Studio container, which
        arrives through pasta's host-loopback mapping. Setting an API key turns
        the check off instead.
      '';
      example = [ "host.containers.internal" "169.254.1.2" ];
    };

    beforeLoad = mkOption {
      type = types.str;
      default = "";
      description = ''
        Command run before the engine loads (`--before-load`), e.g. asking Unsloth Studio
        to unload its model so Strata gets the VRAM. A failing hook keeps the engine
        unloaded and returns the error to the caller. Empty runs nothing.
      '';
    };

    dataOnDataVolume = mkOption {
      type = types.bool;
      default = false;
      description = ''
        Store everything Strata reads and writes - the model files (the data
        folder `~/.local/share/Strata-data`: models/, packs/, mtp/, dflash2/)
        and the runtime tree (`~/.local/share/strata`: venv, engine links, run
        configs, logs) - on the separate `/data` LUKS+btrfs volume instead of
        the home partition. The activation script moves each tree to `/data`
        and leaves a symlink in its place, so Strata keeps using the
        `~/.local/share` paths its settings and run configs already name, and a
        fresh setup downloads straight to `/data`. Nothing is rewritten: the
        absolute `--native`/`--pack`/`--mtp` paths in the run configs resolve
        through the symlinks.
        First run on a host that already has data: `strata.service` is stopped
        for the move (the engine mmaps the model files), so close the desktop
        app too. The move is a copy, not a rename: it takes minutes per 100 GB
        and needs that much free space on `/data`, which the script checks
        first and warns about instead of starting a move it cannot finish.
        Requires the `/data` volume to be mounted.
      '';
    };

    defaultConfig = mkOption {
      type = types.str;
      default = "";
      example = "strata-iq2_xs.json";
      description = ''
        Config file (name under the Strata home, or an absolute path) that
        `strata-server` serves. "" lets the most recently written config win.
      '';
    };
  };

  config = mkMerge [
    (mkIf cfg.enable {
      assertions = [
        {
          # `vision` means "serve images by default", which needs the encoder
          # binary in the package. Only the option DEFAULT ties the two, so an
          # explicit `visionEncoder = false` would otherwise produce a package
          # that is told to serve images it cannot encode.
          assertion = !cfg.vision || cfg.visionEncoder;
          message = "strata.vision = true needs strata.visionEncoder = true: the package must ship the strata-vision encoder it is told to serve with.";
        }
        {
          # Desktop app and Terminal must be the same version: the AppImage
          # cannot update itself from the Nix store (write-protected), so
          # any version mismatch means the app has no engine (ships none
          # since 0.2.5) or a divergent one. Enforced by checking that
          # the desktop package's version (from desktop.nix) equals the
          # Terminal package's version (from default.nix).
          assertion = !cfg.desktop.enable || cfg.package.meta.version == desktop.passthru.version;
          message = "strata.desktop.enable = true requires the desktop AppImage to be at the same version as the Terminal package: Terminal is ${cfg.package.meta.version} but desktop.nix has ${desktop.passthru.version}. Bump both in the same change.";
        }
      ];

      home.packages = [ cfg.package ] ++ optional cfg.desktop.enable desktop.wrapper;

      # The desktop app: the store's executable AppImage symlinked where a user
      # expects an app to live, plus the menu entry and icon. A symlink (not a
      # copy) keeps one copy on disk; upstream's in-app updater cannot replace a
      # store path, so updates come from bumping ./desktop.nix.
      home.file = mkIf cfg.desktop.enable {
        ".local/opt/Strata.AppImage".source = desktop.appImage;
        ".local/share/icons/hicolor/256x256/apps/strata-desktop.png".source = desktop.icon;
        # Written as a file rather than through `xdg.desktopEntries`: that option
        # only lands when `xdg.enable` is set, and this module must not turn on
        # home-manager's whole XDG environment for one menu entry. `Exec` needs an
        # absolute path - the desktop spec has no `%h` field code.
        ".local/share/applications/strata-desktop.desktop".text = ''
          [Desktop Entry]
          Type=Application
          Name=Strata
          GenericName=Local AI
          Comment=Local AI, tuned to one model.
          Exec=${optionalString cfg.desktop.stopServerOnLaunch "env STRATA_APP_STOP_SERVER=1 "}${desktop.wrapper}/bin/strata-app %U
          Icon=strata-desktop
          Categories=Development;
          Terminal=false
          StartupNotify=true
        '';
      };

      systemd.user.services.strata = {
        Unit = {
          Description = "Strata server (${if cfg.vision then "image encoder preloaded" else "engine loads on demand"}; Unsloth Studio's 125B endpoint)";
          After = [ "network-online.target" ];
          # Unlimited restarts: a unit that gives up would leave Studio's 125B
          # endpoint dead. StartLimit* belongs in [Unit] - in [Service] systemd
          # only warns ("Unknown key") and ignores it.
          StartLimitIntervalSec = 0;
        };
        Install = mkIf cfg.autoStart { WantedBy = [ "default.target" ]; };
        Service = {
          Type = "simple";
          # Yield to the desktop while it is in use (packages/ai-slice.nix):
          # CPUWeight 20 against app.slice/session.slice's 100, so the 15-thread
          # expert pool and the CUDA kernel lose to the compositor and the
          # browser only when both want the CPU. Nice orders this unit against
          # the other threads of the same slice; the I/O class keeps a model
          # load (tens of GB) behind interactive reads.
          Slice = "ai.slice";
          Nice = 10;
          IOSchedulingClass = "best-effort";
          IOSchedulingPriority = 7;
          ExecStart = "${cfg.package}/bin/strata-server";
          Environment = [
            "BROWSER=true" # never open a browser from the service
            "STRATA_PORT=${toString cfg.port}"
            "STRATA_HOST=${cfg.host}"
            "STRATA_IDLE_UNLOAD=${toString cfg.idleUnloadSeconds}"
          ]
          ++ optional (cfg.minFreeVramMib > 0) "STRATA_MIN_FREE_VRAM=${toString cfg.minFreeVramMib}"
          ++ optional (cfg.allowedHosts != [ ]) "STRATA_ALLOWED_HOSTS=${concatStringsSep "," cfg.allowedHosts}"
          ++ optional (cfg.beforeLoad != "") "STRATA_BEFORE_LOAD=${cfg.beforeLoad}"
          ++ optional (cfg.defaultConfig != "") "STRATA_CONFIG=${cfg.defaultConfig}";
          # MAP_HUGETLB for the expert arena is charged to RLIMIT_MEMLOCK.
          LimitMEMLOCK = "infinity";
          # No setup yet (no venv/config): exit cleanly with guidance instead of
          # restart-looping.
          Restart = "on-failure";
          RestartSec = "10s";
        };
      };

      # Put both Strata trees on the /data volume and leave a symlink in each
      # old place. Follows the same pattern as ~/sync and ~/roms in
      # common-hm.nix. The symlinks are the whole migration: the model files,
      # packs and MTP layers move to /data, and every path Strata has already
      # written down - `data_dir` in ~/.config/strata/settings.json, the
      # `--native`/`--pack`/`--mtp`/tokenizer paths in each strata-*.json -
      # keeps resolving through them, so no config needs rewriting and a fresh
      # setup downloads to /data too.
      home.activation.strata-dataOnDataVolume = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        if [ "${lib.boolToString cfg.dataOnDataVolume}" != "true" ]; then
          exit 0
        fi
        if ! mountpoint -q /data 2>/dev/null; then
          echo "warning: strata.dataOnDataVolume = true but /data is not mounted" >&2
          exit 0
        fi
        # systemctl --user talks to the user manager over its private socket,
        # which XDG_RUNTIME_DIR names. Home-manager's activation does not
        # always carry it, so set the standard location when it is missing.
        XDG_RUNTIME_DIR=''${XDG_RUNTIME_DIR:-/run/user/''$(id -u)}
        export XDG_RUNTIME_DIR
        SYSTEMCTL=$(command -v systemctl 2>/dev/null || true)
        STOPPED=0
        # No bus, no stop: say so loudly, because moving the files under a
        # running engine is the one case this script cannot make safe.
        if [ -n "$SYSTEMCTL" ] && ! "$SYSTEMCTL" --user is-system-running >/dev/null 2>/dev/null; then
          echo "warning: cannot reach the user systemd: strata.service is NOT stopped for the move. Stop the model first: systemctl --user stop strata, and close the desktop app." >&2
          SYSTEMCTL=""
        fi
        # The engine mmaps the model files, and a reload half-way through the
        # copy would find them missing: stop the server once, before the first
        # move.
        stop_strata() {
          if [ "$STOPPED" = 1 ] || [ -z "$SYSTEMCTL" ]; then
            return 0
          fi
          if "$SYSTEMCTL" --user is-active --quiet strata.service 2>/dev/null; then
            $DRY_RUN_CMD "$SYSTEMCTL" --user stop strata.service
            STOPPED=1
          fi
          return 0
        }
        # name of the folder under ~/.local/share : the folder on /data.
        $DRY_RUN_CMD mkdir -p "$HOME/.local/share"
        for tree in strata:/data/strata Strata-data:/data/Strata-data; do
          name=''${tree%%:*}
          data_dir=''${tree#*:}
          link_dir="$HOME/.local/share/$name"
          $DRY_RUN_CMD mkdir -p "$data_dir"
          if [ -L "$link_dir" ] && [ "$(readlink -f "$link_dir" 2>/dev/null)" = "$data_dir" ]; then
            continue
          fi
          if [ -e "$link_dir" ] && [ ! -L "$link_dir" ]; then
            # A real tree with data in it: move the contents out, then drop the
            # symlink onto the directory the move emptied.
            stop_strata
            need=$(du -sk "$link_dir" 2>/dev/null | cut -f1) || need=""
            avail=$(df -Pk /data 2>/dev/null | awk 'NR == 2 { print $4 }') || avail=""
            if [ -n "$need" ] && [ -n "$avail" ] && [ "$need" -gt "$avail" ]; then
              echo "warning: /data has $avail KB free, $link_dir needs $need KB: leaving it on the home partition" >&2
              continue
            fi
            echo "Strata: moving $link_dir to $data_dir (the engine is stopped; close the desktop app too)..." >&2
            $DRY_RUN_CMD mv "$link_dir"/* "$data_dir"/ 2>/dev/null || true
            $DRY_RUN_CMD mv "$link_dir"/.[!.]* "$data_dir"/ 2>/dev/null || true
            $DRY_RUN_CMD mv "$link_dir"/..?* "$data_dir"/ 2>/dev/null || true
            if ! $DRY_RUN_CMD rmdir "$link_dir" 2>/dev/null; then
              echo "warning: $link_dir is not empty after the move: keeping the directory, no symlink" >&2
              continue
            fi
          fi
          $DRY_RUN_CMD ln -sfn "$data_dir" "$link_dir"
          echo "Strata: $link_dir -> $data_dir" >&2
        done
        ${lib.optionalString cfg.autoStart ''
        if [ "$STOPPED" = 1 ]; then
          $DRY_RUN_CMD "$SYSTEMCTL" --user start strata.service
        fi
        ''}
        ${lib.optionalString (!cfg.autoStart) ''
        if [ "$STOPPED" = 1 ]; then
          echo "Strata: strata.service was stopped for the move and stays stopped (strata.autoStart = false): systemctl --user start strata" >&2
        fi
        ''}
      '';
    })

    # The desktop app only makes sense beside the package it shares models and
    # run configs with. Its files live in the block above (mkIf cfg.enable);
    # saying so here beats an option that silently installs nothing.
    (mkIf cfg.desktop.enable {
      assertions = [
        {
          assertion = cfg.enable;
          message = "strata.desktop.enable = true needs strata.enable = true: the app shares this package's models, packs and run configs.";
        }
      ];
    })
  ];
}
