# Unsloth Studio (https://unsloth.ai, github.com/unslothai/unsloth) — the
# local LLM inference web UI + OpenAI/Anthropic-compatible API server — as a
# home-manager module.
#
# Studio is not in nixpkgs and upstream installs it imperatively (curl | sh
# into ~/.unsloth), so this module is activation scripts + systemd user units
# around that install. Extracted from users/nicky/nicky-hm.nix, where it ran
# on laptop-p16 only; it is now enabled for nicky on every host so the local
# System One endpoint exists everywhere.
#
# The Decision API (Studio → Settings → API → Decision API → "Serve
# requests") serves open System One decision models (Laya, Clef, ...) behind
# a TypeSafe-compatible POST /v1/systemone on the SAME port as the web UI.
# Harness clients (users/opencode.nix), gated on laptop-p16: the `systemone`
# MCP reads the native /mcp/decisions mount with one raw `decide` tool, and the
# systemone plugin (llm-harness-plugins/systemone) posts its packaged judgments
# to /v1/systemone with the owner key. No third-party composed MCP judgment
# server is registered: it covered the same primitive through `npx -y`, and the
# plugin covers it locally.
#
# Model and device are picked in that same panel and stored in Studio's DB
# (~/.unsloth/studio/studio.db, app_settings rows), not here — deliberately.
# The env overrides (UNSLOTH_SYSTEMONE_{MODEL,DEVICE,DISABLE}) do not supply
# a default, they LOCK the value: device_locked() makes validate() reject any
# GUI change. Leaving them unset keeps the panel editable.
#
# Fallbacks when the rows are absent or unrecognised: model
# laya-multilingual, device cpu. CPU is the deliberate one — a CUDA context
# opened in Studio's backend is never returned
# (core/systemone/laya_runtime.py), so Laya on the dGPU holds VRAM for as
# long as the backend lives, beside Strata's arena and llama-server's models.
#
# Checkpoints (core/systemone/catalog.py — this is the list the panel shows,
# and it is longer than the Laya family). The three Laya ones are subfolders of
# convaiinnovations/laya and download on first use:
#   laya-multilingual      678 MB  mmBERT-base, 1024 tok, 100+ languages
#   laya-english           846 MB  ModernBERT, 512 tok
#   laya-typed-decisions   846 MB  English, four typed-decision workflows
# The catalog also lists laya-gguf and third-party decision models (clef,
# clef-flash, kev-0.8b/4b/9b, lev, julia-1, openjev, bespoke-nimble-9b-v3), some
# flagged llama.cpp-only — that names the serving backend, not a GPU
# requirement. With device = cpu every checkpoint runs CPU-only, beside Strata
# instead of competing for the A3000; what you pay is latency. One forward pass
# on laya-multilingual is ~120 ms measured, while the autoregressive kev-* ones
# take seconds (kev-0.8b) to tens of seconds (kev-9b) per decision, and each
# swap evicts the resident model. The 120 ms checkpoint is therefore the default
# and the large ones are reached only by explicit escalation — the
# `systemone_deep` plugin tool in the harness repo.
#
# "Serve requests" itself (a DB row with no env equivalent) and "Keyless API
# access" (localhost requests skip the bearer key) stay per-install GUI
# settings.
#
# ONE INSTANCE PER HOST: Studio installs per-user into $HOME and binds the
# port below, so a second user enabling this on the same machine would
# collide; a second instance needs its own $HOME prefix as well as its own
# port. Other users on the host simply point their clients at
# http://127.0.0.1:<port>. For the API to be up no matter who is logged in,
# the host must set `users.users.nicky.linger = true` (all three hosts do).
# Today it is enabled for nicky only; aeiuno's opencode reaches the same
# endpoint (users/aeiuno/aeiuno-hm.nix records why, and how to give her her
# own on a host she owns alone: the import plus `unsloth-studio.enable`).
#
# This file is the NATIVE backend only. `unsloth-studio.backend = "container"`
# (./container.nix) runs upstream's image under rootless podman instead: it is
# the supported userland on CachyOS, where install.sh, the in-place llama.cpp
# rebuilds and the self-update all behave as upstream expects. Everything below
# is gated on backend = "native", so the two never share a port.
{ config, lib, pkgs, ... }:
with lib;
let
  cfg = config.unsloth-studio;
  # NixOS runtime for the installer's out-of-store prebuilts. They are
  # generic Linux binaries and do not run as-is on NixOS (2026-11-03,
  # laptop-xps):
  #  - their PT_INTERP is /lib64/ld-linux-x86-64.so.2, which on NixOS
  #    26.05 is the stub-ld stub, so the kernel refuses to start them
  #    (llama-server exit 127, "Could not start dynamically linked
  #    executable"); the fix is exec'ing them through the store's real
  #    glibc interpreter (see llama-server-nixos below);
  #  - their C/C++ runtimes are not on the standard library search path
  #    (numpy 2.5: libstdc++.so.6, libz.so.1; torch / Unsloth's
  #    llama.cpp build: libstdc++, libgomp, libssl/libcrypto), so the
  #    service and update units get LD_LIBRARY_PATH (gcc.cc is the raw
  #    compiler drv; its lib output is the gcc-15 runtime set).
  unslothRuntimeLibs = lib.makeLibraryPath [
    pkgs.openssl
    pkgs.zlib
    pkgs.gcc.cc.lib
    pkgs.gcc.cc.libgcc
  ];
  realGlibcLd = "${pkgs.glibc}/lib/ld-linux-x86-64.so.2";
in
{
  # The `ai.slice` both inference stacks run in (see ../ai-slice.nix), imported
  # here so the budget follows the package instead of one user's config.
  imports = [ ./container.nix ./handoff.nix ../ai-slice.nix ];

  options.unsloth-studio = {
    enable = mkEnableOption "Unsloth Studio (local inference web UI + API; Decision API for System One models)";

    port = mkOption {
      type = types.port;
      default = 8888;
      description = "TCP port for the Studio web UI, the OpenAI-compatible API and the Decision API (/v1/systemone).";
    };

    strataGpuHandoff = mkOption {
      type = types.bool;
      default = false;
      description = ''
        Hand the GPU over from Strata on every model load: pin Studio's llama-server to a
        wrapper that unloads the Strata engine first (see `.unsloth/llama.cpp/build/bin/
        llama-server-handoff`). Only meaningful on the host that runs `strata` with
        `strata.enable`; elsewhere it would pin a binary path that may not exist yet.
      '';
    };
  };

  config = mkIf (cfg.enable && cfg.backend == "native") {
    # Install Studio from the official installer script (same pattern as
    # Tresorit in nicky-hm.nix). install.sh puts the CLI at
    # ~/.local/bin/unsloth, the venv under ~/.unsloth/studio/unsloth_studio
    # and data under ~/.local/share/unsloth. UNSLOTH_SKIP_AUTOSTART=1 is the
    # installer's documented non-interactive switch for piped installs (the
    # "Start now?" prompt also only appears on a tty, so hm activation is
    # non-interactive either way); the service below starts Studio instead.
    # timeout prevents a hung switch.
    #
    # The trigger is a health probe, not just file existence: an interrupted
    # install (a laptop sleeping or the lid closing mid-run) leaves every
    # file the -x checks see but the venv half-resolved - on 2026-11-02 an
    # update interrupted on laptop-xps left it without the backend's web
    # stack, and every `unsloth studio` boot died on `import uvicorn` in a
    # 15 s crash loop until a rebuild re-ran the installer. The probe
    # imports exactly the two modules the backend needs to serve (no torch,
    # so it is fast on a healthy venv); a miss re-runs install.sh, whose
    # manifest/cache make that a targeted repair of the missing packages
    # rather than a full reinstall.
    home.activation.installUnsloth = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      venv_python="$HOME/.unsloth/studio/unsloth_studio/bin/python"
      if [ ! -x "$HOME/.local/bin/unsloth" ] || [ ! -x "$venv_python" ] \
         || ! "$venv_python" -c "import uvicorn, fastapi" >/dev/null 2>&1; then
        echo "Installing Unsloth Studio (or repairing a broken install)..."
        # One bash -c with pipefail so a curl failure is not masked by the
        # right-hand sh (and so $DRY_RUN_CMD guards the whole pipeline, not
        # just the left side). The installer env vars go on the sh side.
        # The installer script itself is pinned by hash (fetched by Nix at
        # build time); only the payload it downloads from upstream remains
        # mutable. pipefail: a failed fetch must not be masked by `sh`.
        #
        # The activation runs as the home-manager system service, whose PATH
        # is a fixed handful of coreutils/findutils/grep/sed/systemd bins -
        # no curl, awk, tar, gzip or xz. install.sh hard-fails its dependency
        # check without curl (or wget) and uses awk for its space check, so
        # on a NixOS host the first run dies with "missing: curl (or wget)"
        # and "awk: command not found" (2026-11-02 on laptop-xps). It only
        # ever worked on hosts where install.sh ran from a normal user
        # environment (laptop-p16 is CachyOS, /usr/bin has all of this).
        # Prepend the standard tools it needs; the rest (find, sed, grep,
        # coreutils) the activation PATH already carries.
        #
        # nodejs_24 is there on purpose: without a suitable Node on PATH the
        # installer downloads a prebuilt nodejs.org binary, which is a
        # dynamically linked glibc executable that NixOS refuses to run
        # (2026.11 laptop-xps: /lib64/ld-linux-x86-64.so.2 is the stub-ld
        # stub, the node step died with "NixOS cannot run dynamically linked
        # executables", and the failed setup rolled the whole install back).
        # setup.sh has a documented system-Node path instead ("install Node
        # >= 20.19 with npm >= 11 yourself and re-run"), so we hand it one.
        # It must be 24, not 22: node 22 ships npm 10, below the npm >= 11
        # floor, and the decision code rejects it.
        $DRY_RUN_CMD ${pkgs.bash}/bin/bash -o pipefail -c '
          export PATH=${lib.makeBinPath [
            pkgs.bash
            pkgs.curl
            pkgs.gawk
            pkgs.gnutar
            pkgs.gzip
            pkgs.xz
            pkgs.git
            pkgs.python3
            pkgs.nodejs_24
          ]}:$PATH
          # The PyPI wheels in the venv (numpy/torch) need the store C/C++
          # runtimes to import; without this the installer `import torch`
          # classification and any probe against the venv fail on NixOS.
          # (Bare $VAR on purpose: a dollar-brace form would be a Nix
          # interpolation inside this string.)
          export LD_LIBRARY_PATH=${unslothRuntimeLibs}:$LD_LIBRARY_PATH
          env UNSLOTH_SKIP_AUTOSTART=1 NO_COLOR=1 ${pkgs.bash}/bin/sh ${pkgs.fetchurl {
            url = "https://unsloth.ai/install.sh";
            sha256 = "sha256-bnV8OcVEcBLTBVuxWhFNUb1h6EhX787VBEdfcao0JFQ=";
          }}
        ' </dev/null || echo "unsloth-studio: installer failed (see output above); continuing" >&2
        # The line above swallows the installer's own failure, so verify the
        # install actually landed: a failed repair must be reported as such
        # here, not rediscovered as the next crash loop. (A venv that was
        # never created reports the same way.)
        if ! "$venv_python" -c "import uvicorn, fastapi" >/dev/null 2>&1; then
          echo "unsloth-studio: install ran but the backend is still missing its web stack; re-run the rebuild to retry" >&2
        fi
      fi
    '';

    # Unsloth Desktop (the native Tauri front-end). Additive and independent
    # of Studio above: the desktop app reuses the SAME backend/venv/HF-cache
    # (`~/.unsloth/studio`) and, at runtime, attaches to (or starts) that
    # backend — so the studio service/launcher/updater and the opencode
    # provider are all left untouched. It ships only as a ~180 MB AppImage
    # (the .deb adds nothing but webkit/gtk deps, which the AppImage
    # bundles); like the Studio install it is not in nixpkgs, so fetch the
    # rolling "latest" release asset imperatively. The app self-updates
    # afterwards, so this only downloads when the file is missing — delete it
    # to force a refresh. The menu icon is extracted once from the AppImage.
    home.activation.installUnslothDesktop = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      desktop_dir="$HOME/.local/share/unsloth-desktop"
      app="$desktop_dir/Unsloth-Desktop.AppImage"
      icon="$HOME/.local/share/icons/hicolor/512x512/apps/unsloth-studio.png"
      $DRY_RUN_CMD mkdir -p "$desktop_dir" "$(dirname "$icon")"
      if [ ! -x "$app" ]; then
        echo "Installing Unsloth Desktop..."
        # Pinned release (fetchurl verifies the hash): "releases/latest"
        # downloaded and installed whatever GitHub served at switch time.
        UNSLOTH_DESKTOP_APPIMAGE=${pkgs.fetchurl {
          url = "https://github.com/unslothai/unsloth/releases/download/v0.1.916-beta/Unsloth-Desktop-Linux.AppImage";
          sha256 = "sha256-OiGZGPiYYecvewSlc3uV6ZSulaivZ54FJCO2PouDf54=";
        }}
        $DRY_RUN_CMD ${pkgs.coreutils}/bin/install -Dm0755 "$UNSLOTH_DESKTOP_APPIMAGE" "$app"
      fi
      if [ ! -f "$icon" ] && [ -x "$app" ]; then
        tmp="$(${pkgs.coreutils}/bin/mktemp -d)"
        if ( cd "$tmp" && "$app" --appimage-extract \
             usr/share/icons/hicolor/512x512/apps/unsloth-studio.png >/dev/null 2>&1 ); then
          $DRY_RUN_CMD cp -f \
            "$tmp/squashfs-root/usr/share/icons/hicolor/512x512/apps/unsloth-studio.png" \
            "$icon"
        fi
        $DRY_RUN_CMD rm -rf "$tmp"
      fi
    '';

    home.file = {
      # Service launcher: no-op while Studio is not installed yet, so the
      # unit never crash-loops during the first activation. The nixpkgs
      # node is prepended because the backend resolves Node as
      # system-on-PATH first, else the isolated install
      # (utils/node_runtime.py) - and on NixOS the isolated one can never
      # exist (the nodejs.org prebuilt hits the stub-ld wall, see the
      # installer comment above), so the nixpkgs node is the runtime for
      # the Node-backed features (OXC data-recipe validator, frontend
      # rebuilds).
      ".local/bin/unsloth-studio-launcher.sh" = {
        executable = true;
        text = ''
          #!/usr/bin/env bash
          if [ ! -x "$HOME/.local/bin/unsloth" ]; then
            echo "unsloth CLI not installed; skipping" >&2
            exit 0
          fi
          export PATH=${lib.makeBinPath [pkgs.nodejs_24]}:$PATH
          exec "$HOME/.local/bin/unsloth" studio -p ${toString cfg.port}
        '';
      };
      # Model-load hook for the Strata host: Studio spawns this instead of the
      # managed llama-server (LLAMA_SERVER_PATH, set on the unit below), so the
      # GPU is freed at the moment a model is picked - not only when the
      # service starts. It lives in build/bin beside the real binary on
      # purpose, for two reasons: Studio globs libggml-*.so next to the binary
      # it runs (a shim elsewhere would read as a CPU-only build), and
      # _is_unsloth_managed_binary / _llama_install_root only resolve a binary
      # under ~/.unsloth/llama.cpp (pinned elsewhere, Studio would treat
      # llama.cpp as user-owned and stop offering its updates). exec'ing the
      # real binary keeps $ORIGIN, backend loading and the weekly
      # `unsloth studio update` (which rebuilds llama-server in place) intact;
      # if a rebuild ever removes this file, discovery falls through to the
      # managed binary and the link comes back on the next switch.
      ".unsloth/llama.cpp/build/bin/llama-server-handoff" = lib.mkIf cfg.strataGpuHandoff {
        executable = true;
        text = ''
          #!/usr/bin/env bash
          # Free the GPU (unload Strata) before Studio's llama-server allocates.
          # Never fails the load for the handoff's sake: if Strata is down or
          # still busy the helper warns on stderr and llama-server starts
          # anyway. That is deliberate - the card may still have room for a
          # small model (the helper's own budget follows its wait=), and a hard
          # failure here would block every load on a busy 125B endpoint even
          # when this model would have fitted. llama.cpp reports its own
          # cudaMalloc failure if it truly does not fit.
          set -u
          root="$HOME/.unsloth/llama.cpp"
          real="''${LLAMA_SERVER_REAL:-}"
          if [ -z "$real" ]; then
            for candidate in "$root/build/bin/llama-server" "$root/llama-server"; do
              [ -x "$candidate" ] && { real="$candidate"; break; }
            done
          fi
          if [ -z "$real" ] || [ ! -x "$real" ]; then
            echo "llama-server-handoff: no llama-server under $root" >&2
            exit 127
          fi
          if [ "$real" = "$0" ]; then
            echo "llama-server-handoff: refusing to exec itself ($real)" >&2
            exit 127
          fi

          # Capability probes never touch the GPU: do not evict Strata for them.
          for arg in "$@"; do
            case "$arg" in
              --version | --help | -h | --list-devices | --build-info) exec "$real" "$@" ;;
            esac
          done

          "$HOME/.local/bin/unsloth-studio-free-gpu.sh" || true
          exec "$real" "$@"
        '';
      };
      # Interpreter shim for the non-Strata (NixOS) hosts: Studio spawns this
      # instead of the managed llama-server (LLAMA_SERVER_PATH, set on the
      # unit below). Unsloth's prebuilt llama.cpp is a generic Linux binary
      # whose PT_INTERP is /lib64/ld-linux-x86-64.so.2 - the stub-ld stub on
      # NixOS 26.05 - so the kernel refuses to start it (exit 127, 2026-11-03
      # on laptop-xps: "Could not start dynamically linked executable").
      # exec'ing the binary through the store's real glibc interpreter is
      # equivalent, and LD_LIBRARY_PATH supplies the C/C++ runtimes the
      # prebuilt links against (see the let-block). Same home as the handoff
      # (build/bin) for the same libggml-glob / managed-binary reasons, and
      # the same recovery if an update replaces build/bin: the pin comes back
      # on the next switch.
      #
      # The cd before exec is load-bearing: executed through an explicit
      # interpreter, the kernel reports the INTERPRETER as /proc/self/exe,
      # and llama.cpp's backend discovery (ggml-backend-reg.cpp) enumerates
      # the exe's directory for libggml-cpu-*.so - it would scan the glibc
      # store dir, find nothing, and die "no backends are loaded" (silent in
      # release builds). Its documented fallback search path is the current
      # directory, so run from the binary's own dir (2026-11-03, laptop-xps).
      ".unsloth/llama.cpp/build/bin/llama-server-nixos" = lib.mkIf (!cfg.strataGpuHandoff) {
        executable = true;
        text = ''
          #!/usr/bin/env bash
          bin_dir="$(cd "$(dirname "$0")" && pwd)"
          real="$bin_dir/llama-server"
          if [ ! -x "$real" ] || [ "$real" = "$0" ]; then
            echo "llama-server-nixos: no real llama-server at $real" >&2
            exit 127
          fi
          export LD_LIBRARY_PATH=${unslothRuntimeLibs}:$LD_LIBRARY_PATH
          # llama.cpp finds its ggml backends via the exe dir or the cwd;
          # through an explicit interpreter the exe dir is the glibc store
          # dir, so the cwd has to be the binary's own directory.
          cd "$bin_dir" || exit 127
          exec ${realGlibcLd} "$real" "$@"
        '';
      };
      # Update wrapper for the systemd timer. The installer's own update path
      # is `unsloth studio update` (install.sh runs exactly that), so updates
      # go through the CLI, not a reinstall. Skips cleanly while not
      # installed. Same nodejs_24 PATH as the installer: the update re-runs
      # setup.sh, whose node step probes PATH for a system Node before
      # falling back to the prebuilt download - on NixOS that fallback can
      # never work (stub-ld), so every weekly update would fail its setup
      # and roll the environment back instead of applying the release.
      ".local/bin/unsloth-update.sh" = {
        executable = true;
        text = ''
          #!/usr/bin/env bash
          if [ ! -x "$HOME/.local/bin/unsloth" ]; then
            echo "unsloth CLI not installed; skipping update" >&2
            exit 0
          fi
          export PATH=${lib.makeBinPath [pkgs.nodejs_24]}:$PATH
          exec "$HOME/.local/bin/unsloth" studio update
        '';
      };
    };

    # Desktop launcher for Unsloth Desktop (AppImage installed by
    # installUnslothDesktop above). The activation drops the icon at
    # ~/.local/share/icons/hicolor/512x512/apps/unsloth-studio.png, and
    # StartupWMClass matches the Tauri window so the launcher follows the app.
    xdg.desktopEntries.unsloth-desktop = {
      name = "Unsloth";
      genericName = "Local AI models";
      comment = "Run and train AI models locally (Unsloth Desktop)";
      exec = "${config.home.homeDirectory}/.local/share/unsloth-desktop/Unsloth-Desktop.AppImage %u";
      icon = "unsloth-studio";
      terminal = false;
      type = "Application";
      categories = [ "Utility" "Development" ];
      mimeType = [ "x-scheme-handler/unsloth" ];
      settings.StartupWMClass = "unsloth-studio";
    };

    systemd.user.services = {
      # Always-on Studio: the web UI/API and the Decision API
      # (/v1/systemone + the /mcp/decisions mount), which the `systemone` MCP
      # and the systemone plugin call. Needs linger on the NixOS side to survive
      # logout (see the header comment).
      unsloth-studio = {
        Unit = {
          Description = "Unsloth Studio - local LLM inference web UI";
          After = [ "network-online.target" ];
        };
        Install = {
          WantedBy = [ "default.target" ];
        };
        Service = {
          Type = "simple";
          # Yield to the desktop while it is in use (packages/ai-slice.nix):
          # the backend loads numpy/torch and picks one llama.cpp thread per
          # core, so it joins the same slice as the container backend below
          # (./container.nix) and Strata (packages/strata/home.nix).
          Slice = "ai.slice";
          Nice = 10;
          IOSchedulingClass = "best-effort";
          IOSchedulingPriority = 7;
          ExecStart = "${config.home.homeDirectory}/.local/bin/unsloth-studio-launcher.sh";
          # On the Strata host, Studio's models own the GPU while it runs: ask
          # the Strata server (if up) to unload its 125B engine first. The '-'
          # prefix keeps "not running" / "already unloaded" from blocking the
          # unit; the helper logs what it found. (If a STRATA_API_KEY is ever
          # set, the curl needs to send it.)
          ExecStartPre = optional cfg.strataGpuHandoff "-${config.home.homeDirectory}/.local/bin/unsloth-studio-free-gpu.sh";
          # NixOS runtime for the prebuilts (see the let-block): the backend
          # process itself imports the venv's numpy/torch, which need the
          # store C/C++ runtimes. Every model load starts through the
          # pinned llama-server: the Strata handoff on the Strata host (the
          # engine is unloaded at the moment a model is chosen), the
          # interpreter shim on the NixOS hosts.
          Environment =
            [ "LD_LIBRARY_PATH=${unslothRuntimeLibs}" ]
            ++ optional cfg.strataGpuHandoff
              "LLAMA_SERVER_PATH=${config.home.homeDirectory}/.unsloth/llama.cpp/build/bin/llama-server-handoff"
            ++ optional (!cfg.strataGpuHandoff)
              "LLAMA_SERVER_PATH=${config.home.homeDirectory}/.unsloth/llama.cpp/build/bin/llama-server-nixos";
          Restart = "on-failure";
          RestartSec = "15s";
          # ExecStartPre runs the GPU handoff (see ./container.nix): it waits
          # for Strata to unload, which blocks while Strata is generating. The
          # user manager's 15 s default would kill it and fail the unit.
          TimeoutStartSec = "360s";
        };
      };

      # Weekly update of Unsloth Studio. Updates run via
      # `unsloth studio update` (the same command the official install.sh
      # uses), so new releases are picked up without reinstalling.
      unsloth-update = {
        Unit = {
          Description = "Update Unsloth Studio (unsloth studio update)";
        };
        Service = {
          Type = "oneshot";
          ExecStart = "${config.home.homeDirectory}/.local/bin/unsloth-update.sh";
          # The update re-runs setup.sh, which imports the venv's numpy/torch
          # to classify the environment - same store runtimes as the service
          # (see the let-block), or the update dies on the same
          # libstdc++.so.6 ImportError.
          Environment = [ "LD_LIBRARY_PATH=${unslothRuntimeLibs}" ];
          # Large torch/venv downloads can take a while.
          TimeoutStartSec = "1h";
        };
      };
    };

    systemd.user.timers.unsloth-update = {
      Unit = {
        Description = "Weekly Unsloth Studio update";
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
