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
        # One bash -c with pipefail so a curl failure is not masked by the
        # right-hand sh (and so $DRY_RUN_CMD guards the whole pipeline, not
        # just the left side). The installer env vars go on the sh side.
        # The installer script itself is pinned by hash (fetched by Nix at
        # build time); only the payload it downloads from upstream remains
        # mutable. pipefail: a failed fetch must not be masked by `sh`.
        $DRY_RUN_CMD ${pkgs.bash}/bin/bash -o pipefail -c '
          env UNSLOTH_SKIP_AUTOSTART=1 NO_COLOR=1 ${pkgs.bash}/bin/sh ${pkgs.fetchurl {
            url = "https://unsloth.ai/install.sh";
            sha256 = "05krswbirv8k9pjp5ydllvnydkgxay4p5jsivggkmkd35jjql33g";
          }}
        ' </dev/null || echo "unsloth-studio: installer failed (network/upstream); continuing" >&2
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
          url = "https://github.com/unslothai/unsloth/releases/download/v0.1.910-beta/Unsloth-Desktop-Linux.AppImage";
          sha256 = "sha256-5Ak9Z/oqc0jKdz4J9bxZgjLWBdIaAa9RfuoIgO1zbR8=";
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
          # busy engine or an old Strata must not stop Studio from starting —
          # a small model may still fit beside it. The warning says which.
          set -u
          curl=${pkgs.curl}/bin/curl
          url="''${STRATA_URL:-http://127.0.0.1:8080}"
          wait_s="''${STRATA_UNLOAD_WAIT:-120}"

          # /health and /v1/unload both honour STRATA_API_KEY when the server
          # sets one (upstream: /v1/* needs it, /health does not). Sending it
          # when present is harmless without one, and without it a keyed server
          # answers 401 to the unload below.
          auth=()
          [ -n "''${STRATA_API_KEY:-}" ] && auth=(-H "Authorization: Bearer ''${STRATA_API_KEY}")

          # Nothing listening (or no Strata on this host): nothing to free.
          health="$($curl -fsS -m 5 "''${auth[@]}" "$url/health" 2>/dev/null)" || exit 0
          case "$health" in
            *'"loaded":false'*|*'"loaded": false'*) exit 0 ;;
          esac

          echo "strata: unloading the engine to free the GPU for Studio..." >&2
          # 409 = a request is running or queued and ?wait= did not outlast it.
          # 401/403 = an API key this helper does not send. 000 = no answer.
          code="$($curl -sS -m "$((wait_s + 30))" -o /dev/null -w '%{http_code}' \
            -X POST "''${auth[@]}" -H 'Content-Type: application/json' -d '{}' \
            "$url/v1/unload?wait=$wait_s" 2>/dev/null)" || code="000"

          case "$code" in
            200) : ;;
            409) echo "strata: still busy after ''${wait_s}s (a request is running);" \
                      "waiting for it before Studio allocates" >&2 ;;
            401 | 403) echo "strata: unload refused (HTTP $code): set STRATA_API_KEY for this helper" >&2 ;;
            000) echo "strata: no answer to unload; continuing anyway" >&2 ;;
            *) echo "strata: unload answered HTTP $code" >&2 ;;
          esac

          # The reply means the engine is stopping, not that VRAM is back yet:
          # poll /health before letting Studio's llama-server allocate. The
          # budget follows wait_s (a 409 above leaves a request still draining),
          # so it is not a fixed 60 s that can expire while Strata is working.
          i=0
          tries=$(( (wait_s + 60) / 2 ))
          while [ "$i" -lt "$tries" ]; do
            health="$($curl -fsS -m 5 "$url/health" 2>/dev/null)" || break
            case "$health" in
              *'"loaded":false'*|*'"loaded": false'*)
                echo "strata: engine unloaded, GPU free for Studio" >&2
                exit 0 ;;
            esac
            i=$((i + 1))
            ${pkgs.coreutils}/bin/sleep 2
          done

          echo "strata: engine still loaded (unload answered HTTP $code); trying anyway -" \
               "a small model may still fit, a large one may fail to allocate" >&2
          exit 0
        '';
      };
      # The mirror of the helper above: ask Studio to unload ITS model(s) so
      # Strata can have the VRAM. Strata runs this as its --before-load hook
      # (strata.beforeLoad below), so naming a Strata model while Studio holds
      # the card hands it over instead of answering 503 or dying on a failed
      # cudaMalloc. Studio's own contract (verified against the live server,
      # 2026-10-20): POST /api/inference/unload with a REQUIRED model_path, so
      # the loaded ids come from GET /api/inference/status first; a model that
      # is still generating is refused with 409 unless force_cancel_active is
      # set. Non-zero exit is a failing before-load hook (upstream #1997),
      # which keeps Strata unloaded and reports the error to the caller;
      # "nothing loaded" is success, since then there is nothing to free.
      ".local/bin/unsloth-studio-unload.sh" = lib.mkIf cfg.strataGpuHandoff {
        executable = true;
        text = ''
          #!/usr/bin/env bash
          set -u
          curl=${pkgs.curl}/bin/curl
          url="''${STUDIO_URL:-http://127.0.0.1:${toString cfg.port}}"
          cap="''${STUDIO_UNLOAD_WAIT:-120}"
          force="''${STUDIO_FORCE_CANCEL:-true}"

          key="''${STUDIO_API_KEY:-}"
          if [ -z "$key" ] && [ -r "$HOME/.config/opencode/keys/unsloth.key" ]; then
            key="$(cat "$HOME/.config/opencode/keys/unsloth.key")"
          fi
          auth=()
          [ -n "$key" ] && auth=(-H "Authorization: Bearer $key")

          # Distinguish transport failure (Studio not running -> nothing to
          # free) from an HTTP/auth error (Studio is up but we cannot confirm
          # its state -> refuse to pretend VRAM is free).
          status_file="$(${pkgs.coreutils}/bin/mktemp)"
          code="$($curl -sS -m 5 -o "$status_file" -w '%{http_code}' "''${auth[@]}" "$url/api/inference/status" 2>/dev/null)" || code=000
          if [ "$code" = "000" ]; then
            echo "studio-unload: no Studio at $url; nothing to free" >&2
            exit 0
          fi
          case "$code" in
            2*) status="$(cat "$status_file")" ;;
            *)
              echo "studio-unload: Studio returned HTTP $code; cannot confirm that VRAM is free" >&2
              exit 1
              ;;
          esac

          # Every resident model, plus anything mid-load: a load in flight
          # holds VRAM as surely as a resident one does.
          ids="$(printf '%s' "$status" | ${pkgs.python3}/bin/python3 -c '
          import json, sys
          try:
              d = json.load(sys.stdin)
          except Exception:
              sys.exit(2)
          if not isinstance(d, dict):
              sys.exit(2)
          ids = []
          for k in ("loaded", "loading"):
              v = d.get(k) or []
              if isinstance(v, list):
                  ids += [str(x) for x in v if x]
          for i in dict.fromkeys(ids):
              print(i)
          ' 2>/dev/null)"
          _ids_rc=$?
          if [ "$_ids_rc" -ne 0 ]; then
            echo "studio-unload: cannot parse /api/inference/status; refusing to assume Studio is idle" >&2
            exit 2
          fi

          if [ -z "$ids" ]; then
            echo "studio-unload: Studio holds no model; nothing to free" >&2
            exit 0
          fi

          rc=0
          while IFS= read -r id; do
            [ -n "$id" ] || continue
            echo "studio-unload: unloading Studio model '$id' for Strata..." >&2
            body="$(${pkgs.python3}/bin/python3 -c '
          import json, sys
          print(json.dumps({"model_path": sys.argv[1],
                            "force_cancel_active": sys.argv[2] == "true"}))
          ' "$id" "$force")"
            code="$($curl -sS -m "$cap" -o /dev/null -w '%{http_code}' \
              -X POST "''${auth[@]}" -H 'Content-Type: application/json' -d "$body" \
              "$url/api/inference/unload" 2>/dev/null)" || code="000"
            case "$code" in
              200 | 202 | 204)
                echo "studio-unload: '$id' unloaded" >&2 ;;
              409)
                echo "studio-unload: Studio is still generating on '$id' (HTTP 409)" >&2
                rc=1 ;;
              000)
                echo "studio-unload: no answer from Studio unloading '$id'" >&2
                rc=1 ;;
              *)
                echo "studio-unload: unloading '$id' answered HTTP $code" >&2
                rc=1 ;;
            esac
          done <<< "$ids"

          exit "$rc"
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
          ExecStart = "${config.home.homeDirectory}/.local/bin/unsloth-studio-launcher.sh";
          # On the Strata host, Studio's models own the GPU while it runs: ask
          # the Strata server (if up) to unload its 125B engine first. The '-'
          # prefix keeps "not running" / "already unloaded" from blocking the
          # unit; the helper logs what it found. (If a STRATA_API_KEY is ever
          # set, the curl needs to send it.)
          ExecStartPre = optional cfg.strataGpuHandoff "-${config.home.homeDirectory}/.local/bin/unsloth-studio-free-gpu.sh";
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
