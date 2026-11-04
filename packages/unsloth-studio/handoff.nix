# Host-side GPU handoff between Unsloth Studio and Strata (laptop-p16).
#
# Two directions, both plain HTTP on 127.0.0.1, so they outlive the backend
# choice: they are used by the native Studio service (backend = "native") and by
# the container unit (./container.nix, ExecStartPre) alike. Strata runs this
# pair as its --before-load hook and Studio's unit runs the first one before it
# starts, because the A3000 cannot hold the 125B engine and a Studio model at
# the same time.
#
# The one handoff that does NOT survive containerization is the in-load shim
# (LLAMA_SERVER_PATH -> llama-server-handoff): inside the image llama.cpp is
# baked in, so Studio cannot exec a host wrapper at model-load time. That file
# stays in ./home.nix, native only. In container mode the card is freed once,
# before the container starts, plus on demand by Strata's before-load hook.
#
# Container caveat for the unload direction: Studio's keyless-localhost access
# does not hold through a published port (the server sees the podman gateway as
# the source address), so Studio's API key must exist in
# ~/.config/opencode/keys/unsloth.key. Without it the hook answers 401 and
# Strata refuses the load on purpose.
{ config, lib, pkgs, ... }:
with lib;
let
  cfg = config.unsloth-studio;
in
{
  config = mkIf (cfg.enable && cfg.strataGpuHandoff) {
    home.file = {
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
    };
  };
}
