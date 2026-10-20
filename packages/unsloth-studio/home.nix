# Unsloth Studio (https://unsloth.ai, github.com/unslothai/unsloth) — the
# local LLM inference web UI + OpenAI/Anthropic-compatible API server — as a
# home-manager module, in the same style as ../clm/home.nix.
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
# The opencode `jev` MCP (users/opencode.nix) points there. Two GUI toggles
# are per-install, one-time settings this module cannot set declaratively:
# "Serve requests" (downloads the ~678 MB Laya checkpoint on first use) and
# "Keyless API access" (localhost requests skip the bearer key).
#
# ONE INSTANCE PER HOST: Studio installs per-user into $HOME and binds the
# port below, so a second user enabling this on the same machine would
# collide. Other users on the host simply point their clients at
# http://127.0.0.1:<port>. For the API to be up no matter who is logged in,
# the host must set `users.users.nicky.linger = true` (all three hosts do).
# Today it is enabled for nicky only; aeiuno's opencode reaches the same
# endpoint (users/aeiuno/aeiuno-hm.nix records why, and how to give her her
# own on a host she owns alone: the import plus `unsloth-studio.enable`).
{ config, lib, pkgs, ... }:
with lib;
let
  cfg = config.unsloth-studio;
in
{
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

  config = mkIf cfg.enable {
    # Install Studio from the official installer script (same pattern as
    # Tresorit in nicky-hm.nix). install.sh puts the CLI at
    # ~/.local/bin/unsloth, the venv under ~/.unsloth/studio/unsloth_studio
    # and data under ~/.local/share/unsloth. UNSLOTH_SKIP_AUTOSTART=1 is the
    # installer's documented non-interactive switch for piped installs (the
    # "Start now?" prompt also only appears on a tty, so hm activation is
    # non-interactive either way); the service below starts Studio instead.
    # timeout prevents a hung switch.
    home.activation.installUnsloth = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      if [ ! -x "$HOME/.local/bin/unsloth" ] || [ ! -x "$HOME/.unsloth/studio/unsloth_studio/bin/unsloth" ]; then
        echo "Installing Unsloth Studio..."
        $DRY_RUN_CMD ${pkgs.coreutils}/bin/timeout 1800 env \
          UNSLOTH_SKIP_AUTOSTART=1 NO_COLOR=1 \
          ${pkgs.curl}/bin/curl -fsSL https://unsloth.ai/install.sh \
          | ${pkgs.bash}/bin/sh </dev/null
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
        $DRY_RUN_CMD ${pkgs.coreutils}/bin/timeout 1800 \
          ${pkgs.curl}/bin/curl -fL --retry 3 -o "$app" \
          https://github.com/unslothai/unsloth/releases/latest/download/Unsloth-Desktop-Linux.AppImage
        $DRY_RUN_CMD chmod +x "$app"
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
      # unit never crash-loops during the first activation.
      ".local/bin/unsloth-studio-launcher.sh" = {
        executable = true;
        text = ''
          #!/usr/bin/env bash
          if [ ! -x "$HOME/.local/bin/unsloth" ]; then
            echo "unsloth CLI not installed; skipping" >&2
            exit 0
          fi
          exec "$HOME/.local/bin/unsloth" studio -p ${toString cfg.port}
        '';
      };
      # Free the GPU before Studio starts: ask the Strata server to unload its
      # 125B engine. Strata's own control contract is `POST /v1/unload` (or
      # `/unload`) with a JSON content type - it rejects anything else with
      # 415/403 to keep other web pages from dropping the model. This used to
      # post /api/inference/unload, which is Unsloth Studio's *own* API on
      # 127.0.0.1:8888, not Strata's: the Strata server answered {"error":
      # "not found"} and Studio's llama-server then died with cudaMalloc OOM
      # while the 125B engine still held the card (2026-10-20 on laptop-p16).
      ".local/bin/unsloth-studio-free-gpu.sh" = {
        executable = true;
        text = ''
          #!/usr/bin/env bash
          # Ask Strata (if it is up) to unload its engine so Studio's own
          # models get the VRAM. Never fails the caller: a missing server, a
          # busy engine or an old Strata must not stop Studio from starting.
          set -u
          curl=${pkgs.curl}/bin/curl
          url="''${STRATA_URL:-http://127.0.0.1:8080}"
          wait_s="''${STRATA_UNLOAD_WAIT:-120}"

          # Nothing listening (or no Strata on this host): nothing to free.
          health="$($curl -fsS -m 5 "$url/health" 2>/dev/null)" || exit 0
          case "$health" in
            *'"loaded":false'*|*'"loaded": false'*) exit 0 ;;
          esac

          echo "strata: unloading the engine to free the GPU for Studio..." >&2
          code="$($curl -sS -m "$((wait_s + 30))" -o /dev/null -w '%{http_code}' \
            -X POST -H 'Content-Type: application/json' -d '{}' \
            "$url/v1/unload?wait=$wait_s" 2>/dev/null)" || code="000"

          # The reply means the engine is stopping, not that VRAM is back yet:
          # poll /health before letting Studio's llama-server allocate.
          i=0
          while [ "$i" -lt 30 ]; do
            health="$($curl -fsS -m 5 "$url/health" 2>/dev/null)" || break
            case "$health" in
              *'"loaded":false'*|*'"loaded": false'*)
                echo "strata: engine unloaded, GPU free for Studio" >&2
                exit 0 ;;
            esac
            i=$((i + 1))
            ${pkgs.coreutils}/bin/sleep 2
          done

          echo "strata: engine still loaded (unload answered HTTP $code); Studio may see little free VRAM" >&2
          exit 0
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
          # busy the helper says so and llama-server starts exactly as before.
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
      # Update wrapper for the systemd timer. The installer's own update path
      # is `unsloth studio update` (install.sh runs exactly that), so updates
      # go through the CLI, not a reinstall. Skips cleanly while not
      # installed.
      ".local/bin/unsloth-update.sh" = {
        executable = true;
        text = ''
          #!/usr/bin/env bash
          if [ ! -x "$HOME/.local/bin/unsloth" ]; then
            echo "unsloth CLI not installed; skipping update" >&2
            exit 0
          fi
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
      # (/v1/systemone) that the opencode `jev` MCP calls. Needs linger on
      # the NixOS side to survive logout (see the header comment).
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
          ExecStart = "${config.home.homeDirectory}/.local/bin/unsloth-studio-launcher.sh";
          # On the Strata host, Studio's models own the GPU while it runs: ask
          # the Strata server (if up) to unload its 125B engine first. The '-'
          # prefix keeps "not running" / "already unloaded" from blocking the
          # unit; the helper logs what it found. (If a STRATA_API_KEY is ever
          # set, the curl needs to send it.)
          ExecStartPre = "-${config.home.homeDirectory}/.local/bin/unsloth-studio-free-gpu.sh";
          # Every model load starts here, so the Strata engine is unloaded at
          # the moment a model is chosen rather than only at service start.
          # See the llama-server-handoff file above.
          Environment = optional cfg.strataGpuHandoff
            "LLAMA_SERVER_PATH=${config.home.homeDirectory}/.unsloth/llama.cpp/build/bin/llama-server-handoff";
          Restart = "on-failure";
          RestartSec = "15s";
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
