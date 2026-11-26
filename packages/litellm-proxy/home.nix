# home-manager wrapper for the LiteLLM proxy (services/litellm-proxy.nix).
#
#   imports = [ ../../packages/litellm-proxy/home.nix ];
#   litellm-proxy.enable = true;   # gated per-host on the inference hosts
#
# Runs the same LiteLLM rank-gateway proxy as the NixOS system service
# (server-nike + laptop-p16 when NixOS), but as a **user systemd service**.
# Reads the shared opencode-keys secret via agenix (same .age file, decrypted
# to the user's home), derives the backend keys + DATABASE_URL into a runtime
# env file, and starts `litellm` with the proxy config.
#
# No PostgreSQL is used: the proxy falls back to SQLite for the admin UI and
# spend logging. The NixOS module uses `--use_prisma_db_push` to push the full
# schema into a system PostgreSQL instance; this module omits that flag and
# skips all Prisma/Node/Prisma-CLI plumbing (the proxy runs fine without it).
# The admin UI still works — it just stores spend data in a local SQLite file.
{ config, lib, pkgs, ... }:

let
  cfg = config.litellm-proxy;

  # Read-only Prisma CLI cache — only needed when --use_prisma_db_push is
  # enabled. This module does NOT use it, so the value is unused and left
  # as a placeholder to keep the interface compatible if someone adds DB back.
  prismaCli = pkgs.runCommand "litellm-prisma-cli-placeholder" { } ''
    mkdir -p $out
  '';

  # Derives /tmp/litellm-proxy.env from the shared opencode-keys secret.
  # Writes: all LITELLM_* keys + LITELLM_MASTER_KEY (which the NixOS
  # derive-keys-env.py forgot to include).
  deriveKeysEnv = pkgs.writeShellApplication {
    name = "litellm-proxy-derive-keys";
    runtimeInputs = [ pkgs.python3 pkgs.jq ];
    text = ''
      import json, os, sys

      # Home-manager agenix decrypts the shared opencode-keys secret to
      # ~/.config/agenix/opencode-keys.env (see users/nicky/nicky-hm.nix
      # age.secrets."opencode-keys.env"). On NixOS the NixOS module
      # mounts it at /etc/secrets/opencode-keys.env — check both.
      HOME_DIR = os.environ.get("HOME", "/home/nicky")
      candidates = [
          HOME_DIR + "/.config/agenix/opencode-keys.env",
          "/etc/secrets/opencode-keys.env",
      ]
      SRC = None
      for p in candidates:
          if os.path.isfile(p):
              SRC = p
              break
      if SRC is None:
          print(f"litellm-proxy: opencode-keys secret not found at {candidates}", file=sys.stderr)
          sys.exit(1)

      DST = "/tmp/litellm-proxy.env"

      # env var -> base URL under which the key is stored in the secret
      mapping = {
          "LITELLM_MASTER_KEY": "http://server-nike.bee-blues.ts.net:4000/v1",
          "LITELLM_UNSLOTH_API_KEY": "http://server-nike.bee-blues.ts.net:8888/v1",
          "LITELLM_HETZNER_API_KEY": "https://inference.hetzner.com/api/v1",
          "LITELLM_DEEPSEEK_API_KEY": "https://api.deepseek.com",
          "LITELLM_ZAI_API_KEY": "https://api.z.ai/api/paas/v4/",
          "LITELLM_KIMI_API_KEY": "https://api.kimi.com/coding/v1",
          "LITELLM_CHEAPERINFERENCE_API_KEY": "https://api.cheaperinference.com/v1",
      }

      with open(SRC) as fh:
          _, _, payload = fh.read().partition("=")
      keys = json.loads(payload.strip())

      missing = []
      lines = []
      for var, url in mapping.items():
          value = keys.get(url)
          if not value:
              missing.append(var)
              print(f"litellm-proxy: no key for {url} in {SRC}; {var} unset", file=sys.stderr)
              continue
          lines.append(f"{var}={value}")

      if missing:
          print(f"litellm-proxy: refusing to start with missing keys: {', '.join(missing)}", file=sys.stderr)
          sys.exit(1)

      # No PostgreSQL: the proxy falls back to SQLite.
      # The NixOS module writes DATABASE_URL here; we leave it unset.
      # lines.append("DATABASE_URL=...")

      fd = os.open(DST, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
      with os.fdopen(fd, "w") as out:
          out.write("\n".join(lines) + "\n")
      print(f"litellm-proxy: wrote {DST} ({len(lines)} keys)")
    '';
  };

  # Writable, pre-restructured copy of the packaged UI.
  # The same preparation the NixOS module does, but under the user's home.
  litellmHomeDir = "$HOME/.local/state/litellm-proxy";
  prepareUi = pkgs.writeShellScript "litellm-prepare-ui-home" ''
    set -euo pipefail

    UI=${litellmHomeDir}/ui
    SRC=${pkgs.litellm}/lib/python3.13/site-packages/litellm/proxy/_experimental/out

    if [ -f "$UI/.litellm_ui_ready" ] && [ "$(cat "$UI/.litellm_source" 2>/dev/null || true)" = "$SRC" ]; then
      exit 0
    fi

    mkdir -p "$UI"
    rm -rf "$UI"/*
    cp -a "$SRC"/. "$UI"/
    chmod -R u+w "$UI"

    find "$UI" -type f -name '*.html' ! -name 'index.html' \
      ! -path "$UI/_next/*" ! -path "$UI/litellm-asset-prefix/*" -print0 |
      while IFS= read -r -d "" f; do
        d="''${f%.html}"
        mkdir -p "$d"
        mv "$f" "$d/index.html"
      done

    printf '%s\n' "$SRC" > "$UI/.litellm_source"
    touch "$UI/.litellm_ui_ready"
  '';

  # The proxy configuration — same as services/litellm-proxy.nix but with
  # laptop-p16's Strata rows pointing to localhost (8080) instead of the
  # Tailscale address on server-nike.
  proxyConfig = ''
    model_list:

      # ===========================================================================
      # RANK LADDER
      # ===========================================================================

      # Sergeant (OR-4) — fast executor. Local first: the Strata instance pair
      # at order 1 (shuffle server-nike + laptop-p16), Unsloth Studio fallback
      # only when Strata is absent (order 2, costs a model load).
      - model_name: "sergeant"
        litellm_params:
          model: openai/swift-1.5-iq3_xxs
          api_base: http://127.0.0.1:8080/v1        # local Strata (this host)
          api_key: strata
          temperature: 0.1
          order: 1
          timeout: 300
          stream_timeout: 180
          num_retries: 1
          max_parallel_requests: 1
        model_info:
          id: sergeant-swift1.5-local
          max_input_tokens: 262144
          input_cost_per_token: 0
          output_cost_per_token: 0
      - model_name: "sergeant"
        litellm_params:
          model: openai/unsloth/NVIDIA-Nemotron-3.5-Bolt-E4B-GGUF
          api_base: http://127.0.0.1:8888/v1
          api_key: os.environ/LITELLM_UNSLOTH_API_KEY
          temperature: 0.1
          order: 2
          timeout: 120
          stream_timeout: 30
          num_retries: 1
        model_info:
          id: sergeant-studio
          max_input_tokens: 128256
          supports_vision: false
          input_cost_per_token: 0
          output_cost_per_token: 0

      # Warrant Officer (OR-8) — Qwen3.6-35B-A3B on Hetzner, with Strata
      # (swift-1.5) as the fallback.
      - model_name: "warrant-officer"
        litellm_params:
          model: openai/Qwen/Qwen3.6-35B-A3B-FP8
          api_base: https://inference.hetzner.com/v1
          api_key: os.environ/LITELLM_HETZNER_API_KEY
          order: 1
          timeout: 300
          stream_timeout: 60
          num_retries: 2
        model_info:
          id: warrant-officer-hetzner
          max_input_tokens: 262144
          supports_vision: false
          input_cost_per_token: 0
          output_cost_per_token: 0
      - model_name: "warrant-officer"
        litellm_params:
          model: openai/swift-1.5-iq3_xxs
          api_base: http://127.0.0.1:8080/v1        # local Strata
          api_key: strata
          order: 2
          timeout: 600
          stream_timeout: 180
          num_retries: 1
          max_parallel_requests: 1
        model_info:
          id: warrant-officer-strata-local
          max_input_tokens: 262144
          supports_vision: false
          input_cost_per_token: 0
          output_cost_per_token: 0

      # Warrant Officer (vision)
      - model_name: "warrant-officer-v"
        litellm_params:
          model: openai/Qwen/Qwen3.6-35B-A3B-FP8
          api_base: https://inference.hetzner.com/v1
          api_key: os.environ/LITELLM_HETZNER_API_KEY
          order: 1
          timeout: 300
          stream_timeout: 60
          num_retries: 2
        model_info:
          id: warrant-officer-v-hetzner
          max_input_tokens: 262144
          supports_vision: true
          input_cost_per_token: 0
          output_cost_per_token: 0
      - model_name: "warrant-officer-v"
        litellm_params:
          model: openai/swift-1.5-iq3_xxs
          api_base: http://127.0.0.1:8080/v1        # local Strata
          api_key: strata
          order: 2
          timeout: 600
          stream_timeout: 180
          num_retries: 1
          max_parallel_requests: 1
        model_info:
          id: warrant-officer-v-strata-local
          max_input_tokens: 262144
          supports_vision: true
          input_cost_per_token: 0
          output_cost_per_token: 0

      # Second Lieutenant (OF-1a)
      - model_name: "second-lieutenant"
        litellm_params:
          model: openai/Qwen3.8-27B
          api_base: https://inference.hetzner.com/v1
          api_key: os.environ/LITELLM_HETZNER_API_KEY
          order: 1
          timeout: 600
          stream_timeout: 120
          num_retries: 2
        model_info:
          id: second-lieutenant-hetzner
          max_input_tokens: 262144
          supports_vision: false
          input_cost_per_token: 0
          output_cost_per_token: 0
      - model_name: "second-lieutenant"
        litellm_params:
          model: openai/swift-1.5-iq3_xxs
          api_base: http://127.0.0.1:8080/v1        # local Strata
          api_key: strata
          order: 2
          timeout: 600
          stream_timeout: 180
          num_retries: 1
          max_parallel_requests: 1
        model_info:
          id: second-lieutenant-strata-local
          max_input_tokens: 262144
          supports_vision: false
          input_cost_per_token: 0
          output_cost_per_token: 0

      # Lieutenant (OF-1b) — Swift 1.5 on Strata. The default model.
      - model_name: "lieutenant"
        litellm_params:
          model: openai/swift-1.5-iq3_xxs
          api_base: http://127.0.0.1:8080/v1        # local Strata
          api_key: strata
          order: 1
          timeout: 600
          stream_timeout: 180
          num_retries: 1
          max_parallel_requests: 1
        model_info:
          id: lieutenant-strata-local
          max_input_tokens: 262144
          supports_vision: false
          input_cost_per_token: 0
          output_cost_per_token: 0

      # Lieutenant (vision)
      - model_name: "lieutenant-v"
        litellm_params:
          model: openai/swift-1.5-iq3_xxs
          api_base: http://127.0.0.1:8080/v1        # local Strata
          api_key: strata
          order: 1
          timeout: 600
          stream_timeout: 180
          num_retries: 1
          max_parallel_requests: 1
        model_info:
          id: lieutenant-v-strata-local
          max_input_tokens: 262144
          supports_vision: true
          input_cost_per_token: 0
          output_cost_per_token: 0

      # ---------------------------------------------------------------------------
      # Paid ranks (explicit selection only)
      # ---------------------------------------------------------------------------

      # Captain (OF-2) — DeepSeek V4.1 Flash
      - model_name: "captain"
        litellm_params:
          model: deepseek/deepseek-flash
          api_key: os.environ/LITELLM_DEEPSEEK_API_KEY
          timeout: 600
          stream_timeout: 120
          num_retries: 2
        model_info:
          id: captain-deepseek
          max_input_tokens: 1048576
          supports_vision: false
      - model_name: "captain-v"
        litellm_params:
          model: deepseek/deepseek-flash
          api_key: os.environ/LITELLM_DEEPSEEK_API_KEY
          timeout: 600
          stream_timeout: 120
          num_retries: 2
        model_info:
          id: captain-v-deepseek
          max_input_tokens: 1048576
          supports_vision: true

      # Captain Commandant (OF-3)
      - model_name: "captain-commandant"
        litellm_params:
          model: openai/glm-5-turbo
          api_base: https://api.z.ai/api/coding/paas/v4
          api_key: os.environ/LITELLM_ZAI_API_KEY
          order: 1
          timeout: 600
          stream_timeout: 120
          num_retries: 2
        model_info:
          id: captain-commandant-zai
          max_input_tokens: 200000
          supports_vision: false
          input_cost_per_token: 0
          output_cost_per_token: 0
      - model_name: "captain-commandant"
        litellm_params:
          model: deepseek/deepseek-v4-pro
          api_key: os.environ/LITELLM_DEEPSEEK_API_KEY
          order: 2
          timeout: 600
          stream_timeout: 120
          num_retries: 2
        model_info:
          id: captain-commandant-deepseek
          max_input_tokens: 1048576
          supports_vision: false

      # Major (OF-4)
      - model_name: "major"
        litellm_params:
          model: openai/kimi-for-coding
          api_base: https://api.kimi.com/coding/v1
          api_key: os.environ/LITELLM_KIMI_API_KEY
          order: 1
          timeout: 600
          stream_timeout: 120
          num_retries: 2
        model_info:
          id: major-kimi
          max_input_tokens: 1048576
          supports_vision: false
          input_cost_per_token: 0
          output_cost_per_token: 0
      - model_name: "major"
        litellm_params:
          model: openai/glm-5.3-flash
          api_base: https://api.z.ai/api/coding/paas/v4
          api_key: os.environ/LITELLM_ZAI_API_KEY
          reasoning_effort: max
          order: 2
          timeout: 600
          stream_timeout: 120
          num_retries: 2
        model_info:
          id: major-zai
          max_input_tokens: 1000000
          supports_vision: false
          input_cost_per_token: 0
          output_cost_per_token: 0
      - model_name: "major"
        litellm_params:
          model: deepseek/deepseek-v4-pro
          api_key: os.environ/LITELLM_DEEPSEEK_API_KEY
          order: 3
          timeout: 600
          stream_timeout: 120
          num_retries: 2
        model_info:
          id: major-deepseek
          max_input_tokens: 1048576
          supports_vision: false

      # Major (vision)
      - model_name: "major-v"
        litellm_params:
          model: openai/kimi-for-coding
          api_base: https://api.kimi.com/coding/v1
          api_key: os.environ/LITELLM_KIMI_API_KEY
          order: 1
          timeout: 600
          stream_timeout: 120
          num_retries: 2
        model_info:
          id: major-v-kimi
          max_input_tokens: 1048576
          supports_vision: true
          input_cost_per_token: 0
          output_cost_per_token: 0
      - model_name: "major-v"
        litellm_params:
          model: openai/glm-5.3-flash
          api_base: https://api.z.ai/api/coding/paas/v4
          api_key: os.environ/LITELLM_ZAI_API_KEY
          reasoning_effort: max
          order: 2
          timeout: 600
          stream_timeout: 120
          num_retries: 2
        model_info:
          id: major-v-zai
          max_input_tokens: 1000000
          supports_vision: true
          input_cost_per_token: 0
          output_cost_per_token: 0

      # Lieutenant Colonel (OF-5)
      - model_name: "lieutenant-colonel"
        litellm_params:
          model: openai/glm-5.3
          api_base: https://api.z.ai/api/coding/paas/v4
          api_key: os.environ/LITELLM_ZAI_API_KEY
          reasoning_effort: max
          order: 1
          timeout: 600
          stream_timeout: 120
          num_retries: 2
        model_info:
          id: lieutenant-colonel-zai
          max_input_tokens: 1000000
          supports_vision: false
          input_cost_per_token: 0
          output_cost_per_token: 0
      - model_name: "lieutenant-colonel"
        litellm_params:
          model: openai/k3
          api_base: https://api.kimi.com/coding/v1
          api_key: os.environ/LITELLM_KIMI_API_KEY
          order: 2
          timeout: 600
          stream_timeout: 120
          num_retries: 2
        model_info:
          id: lieutenant-colonel-kimi-k3
          max_input_tokens: 1048576
          supports_vision: false
          input_cost_per_token: 0
          output_cost_per_token: 0
      - model_name: "lieutenant-colonel"
        litellm_params:
          model: openai/k3-256k
          api_base: https://api.kimi.com/coding/v1
          api_key: os.environ/LITELLM_KIMI_API_KEY
          order: 3
          timeout: 600
          stream_timeout: 120
          num_retries: 2
        model_info:
          id: lieutenant-colonel-kimi-k3-256k
          max_input_tokens: 262144
          supports_vision: false
          input_cost_per_token: 0
          output_cost_per_token: 0

      # Lieutenant Colonel (vision)
      - model_name: "lieutenant-colonel-v"
        litellm_params:
          model: openai/k3
          api_base: https://api.kimi.com/coding/v1
          api_key: os.environ/LITELLM_KIMI_API_KEY
          order: 1
          timeout: 600
          stream_timeout: 120
          num_retries: 2
        model_info:
          id: lc-v-k3
          max_input_tokens: 1048576
          supports_vision: true
          input_cost_per_token: 0
          output_cost_per_token: 0
      - model_name: "lieutenant-colonel-v"
        litellm_params:
          model: openai/k3-256k
          api_base: https://api.kimi.com/coding/v1
          api_key: os.environ/LITELLM_KIMI_API_KEY
          order: 2
          timeout: 600
          stream_timeout: 120
          num_retries: 2
        model_info:
          id: lc-v-k3-256k
          max_input_tokens: 262144
          supports_vision: true
          input_cost_per_token: 0
          output_cost_per_token: 0

      # Brigadier General (OF-6) — k3.1-pro @ Kimi
      - model_name: "brigadier-general"
        litellm_params:
          model: openai/k3.1-pro
          api_base: https://api.kimi.com/coding/v1
          api_key: os.environ/LITELLM_KIMI_API_KEY
          reasoning_effort: high
          timeout: 600
          stream_timeout: 120
          num_retries: 2
        model_info:
          id: brigadier-general-kimi
          max_input_tokens: 1048576
          supports_vision: false
          input_cost_per_token: 0
          output_cost_per_token: 0

      # Brigadier General (vision)
      - model_name: "brigadier-general-v"
        litellm_params:
          model: openai/k3.1-pro
          api_base: https://api.kimi.com/coding/v1
          api_key: os.environ/LITELLM_KIMI_API_KEY
          reasoning_effort: high
          timeout: 600
          stream_timeout: 120
          num_retries: 2
        model_info:
          id: brigadier-general-v-kimi
          max_input_tokens: 1048576
          supports_vision: true
          input_cost_per_token: 0
          output_cost_per_token: 0

      # ===========================================================================
      # EXPLICIT MODEL NAMES
      # ===========================================================================

      # Kimi Code (legacy Allegretto plan)
      - model_name: "k3.1-pro"
        litellm_params:
          model: openai/k3.1-pro
          api_base: https://api.kimi.com/coding/v1
          api_key: os.environ/LITELLM_KIMI_API_KEY
          reasoning_effort: high
          timeout: 600
          stream_timeout: 120
          num_retries: 2
        model_info:
          id: k3.1-pro-kimi
          max_input_tokens: 1048576
          supports_vision: true
          input_cost_per_token: 0
          output_cost_per_token: 0
      - model_name: "k3"
        litellm_params:
          model: openai/k3
          api_base: https://api.kimi.com/coding/v1
          api_key: os.environ/LITELLM_KIMI_API_KEY
          timeout: 600
          stream_timeout: 120
          num_retries: 2
        model_info:
          id: k3-kimi
          max_input_tokens: 1048576
          supports_vision: true
          input_cost_per_token: 0
          output_cost_per_token: 0
      - model_name: "k3-256k"
        litellm_params:
          model: openai/k3-256k
          api_base: https://api.kimi.com/coding/v1
          api_key: os.environ/LITELLM_KIMI_API_KEY
          timeout: 600
          stream_timeout: 120
          num_retries: 2
        model_info:
          id: k3-256k-kimi
          max_input_tokens: 262144
          supports_vision: true
          input_cost_per_token: 0
          output_cost_per_token: 0
      - model_name: "kimi-for-coding"
        litellm_params:
          model: openai/kimi-for-coding
          api_base: https://api.kimi.com/coding/v1
          api_key: os.environ/LITELLM_KIMI_API_KEY
          timeout: 600
          stream_timeout: 120
          num_retries: 2
        model_info:
          id: kimi-for-coding-kimi
          max_input_tokens: 1048576
          supports_vision: true
          input_cost_per_token: 0
          output_cost_per_token: 0

      # Z.ai Coding Plan
      - model_name: "glm-5.3"
        litellm_params:
          model: openai/glm-5.3
          api_base: https://api.z.ai/api/coding/paas/v4
          api_key: os.environ/LITELLM_ZAI_API_KEY
          reasoning_effort: max
          timeout: 600
          stream_timeout: 120
          num_retries: 2
        model_info:
          id: glm-5.3-zai
          max_input_tokens: 1000000
          supports_vision: false
          input_cost_per_token: 0
          output_cost_per_token: 0
      - model_name: "glm-5.3-flash"
        litellm_params:
          model: openai/glm-5.3-flash
          api_base: https://api.z.ai/api/coding/paas/v4
          api_key: os.environ/LITELLM_ZAI_API_KEY
          reasoning_effort: max
          timeout: 600
          stream_timeout: 120
          num_retries: 2
        model_info:
          id: glm-5.3-flash-zai
          max_input_tokens: 1000000
          supports_vision: true
          input_cost_per_token: 0
          output_cost_per_token: 0
      - model_name: "glm-5-turbo"
        litellm_params:
          model: openai/glm-5-turbo
          api_base: https://api.z.ai/api/coding/paas/v4
          api_key: os.environ/LITELLM_ZAI_API_KEY
          timeout: 600
          stream_timeout: 120
          num_retries: 2
        model_info:
          id: glm-5-turbo-zai
          max_input_tokens: 200000
          supports_vision: false
          input_cost_per_token: 0
          output_cost_per_token: 0

      # DeepSeek API (pay-per-token)
      - model_name: "deepseek-flash"
        litellm_params:
          model: deepseek/deepseek-flash
          api_key: os.environ/LITELLM_DEEPSEEK_API_KEY
          timeout: 600
          stream_timeout: 120
        model_info:
          id: deepseek-flash-direct
          max_input_tokens: 1048576

      - model_name: "deepseek-v4-pro"
        litellm_params:
          model: deepseek/deepseek-v4-pro
          api_key: os.environ/LITELLM_DEEPSEEK_API_KEY
          timeout: 600
          stream_timeout: 120
        model_info:
          id: deepseek-v4-pro-direct
          max_input_tokens: 1048576
          supports_vision: false

      # HETZNER FREE CLOUD
      - model_name: "Qwen/Qwen3.6-35B-A3B"
        litellm_params:
          model: openai/Qwen/Qwen3.6-35B-A3B
          api_base: https://inference.hetzner.com/v1
          api_key: os.environ/LITELLM_HETZNER_API_KEY
          timeout: 300
          stream_timeout: 60
          num_retries: 2
        model_info:
          id: hetzner-qwen3.6-35b-a3b
          max_input_tokens: 262144
          supports_vision: false
          input_cost_per_token: 0
          output_cost_per_token: 0

      - model_name: "Qwen/Qwen3.6-35B-A3B-FP8"
        litellm_params:
          model: openai/Qwen/Qwen3.6-35B-A3B-FP8
          api_base: https://inference.hetzner.com/v1
          api_key: os.environ/LITELLM_HETZNER_API_KEY
          timeout: 300
          stream_timeout: 60
          num_retries: 2
        model_info:
          id: hetzner-qwen3.6-35b-a3b-fp8
          max_input_tokens: 262144
          supports_vision: false
          input_cost_per_token: 0
          output_cost_per_token: 0

      - model_name: "Qwen/Qwen3.8-27B"
        litellm_params:
          model: openai/Qwen/Qwen3.8-27B
          api_base: https://inference.hetzner.com/v1
          api_key: os.environ/LITELLM_HETZNER_API_KEY
          timeout: 600
          stream_timeout: 120
          num_retries: 2
        model_info:
          id: hetzner-qwen3.8-27b-prefixed
          max_input_tokens: 262144
          supports_vision: false
          input_cost_per_token: 0
          output_cost_per_token: 0

      - model_name: "Qwen3.8-27B"
        litellm_params:
          model: openai/Qwen3.8-27B
          api_base: https://inference.hetzner.com/v1
          api_key: os.environ/LITELLM_HETZNER_API_KEY
          timeout: 600
          stream_timeout: 120
          num_retries: 2
        model_info:
          id: hetzner-qwen3.8-27b
          max_input_tokens: 262144
          supports_vision: false
          input_cost_per_token: 0
          output_cost_per_token: 0

      # ---------------------------------------------------------------------------
      # UNRANKED — CheaperInference
      # ---------------------------------------------------------------------------
      - model_name: "deepseek-v4.1-flash"
        litellm_params:
          model: openai/deepseek-v4.1-flash
          api_base: https://api.cheaperinference.com/v1
          api_key: os.environ/LITELLM_CHEAPERINFERENCE_API_KEY
          timeout: 600
          stream_timeout: 120
        model_info:
          id: deepseek-v4.1-flash-ci
          max_input_tokens: 1048576
          input_cost_per_token: 0
          output_cost_per_token: 0

      - model_name: "gpt-5.6-luna"
        litellm_params:
          model: openai/gpt-5.6-luna
          api_base: https://api.cheaperinference.com/v1
          api_key: os.environ/LITELLM_CHEAPERINFERENCE_API_KEY
          timeout: 600
          stream_timeout: 120
        model_info:
          id: gpt-5.6-luna-ci
          max_input_tokens: 1050000
          pricing_provider: openai

      - model_name: "claude-sonnet-5.5"
        litellm_params:
          model: openai/claude-sonnet-5.5
          api_base: https://api.cheaperinference.com/v1
          api_key: os.environ/LITELLM_CHEAPERINFERENCE_API_KEY
          timeout: 600
          stream_timeout: 120
        model_info:
          id: claude-sonnet-5.5-ci
          max_input_tokens: 1000000
          input_cost_per_token: 0
          output_cost_per_token: 0

      - model_name: "claude-opus-5.5"
        litellm_params:
          model: openai/claude-opus-5.5
          api_base: https://api.cheaperinference.com/v1
          api_key: os.environ/LITELLM_CHEAPERINFERENCE_API_KEY
          timeout: 600
          stream_timeout: 120
        model_info:
          id: claude-opus-5.5-ci
          max_input_tokens: 1000000
          input_cost_per_token: 0
          output_cost_per_token: 0

      - model_name: "glm-5.3-payg"
        litellm_params:
          model: openai/glm-5.3
          api_base: https://api.cheaperinference.com/v1
          api_key: os.environ/LITELLM_CHEAPERINFERENCE_API_KEY
          timeout: 600
          stream_timeout: 120
        model_info:
          id: glm-5.3-payg-ci
          max_input_tokens: 1000000
          supports_vision: false
          input_cost_per_token: 0
          output_cost_per_token: 0


    # -----------------------------------------------------------------------------
    # Router
    # -----------------------------------------------------------------------------
    router_settings:
      routing_strategy: simple-shuffle
      num_retries: 2
      allowed_fails: 1
      cooldown_time: 5
      enable_pre_call_checks: true

      fallbacks:
        - lieutenant: [second-lieutenant]
        - second-lieutenant: [warrant-officer]
        - lieutenant-v: [warrant-officer-v]

      max_fallbacks: 2

    litellm_settings:
      drop_params: true
      request_timeout: 600

    general_settings:
      master_key: os.environ/LITELLM_MASTER_KEY
  '';

in
{
  options.litellm-proxy = {
    enable = lib.mkEnableOption "LiteLLM proxy (rank gateway for the local + paid LLM backends)";
    port = lib.mkOption {
      type = lib.types.port;
      default = 4000;
      description = "TCP port the proxy listens on.";
    };
  };

  config = lib.mkIf cfg.enable {
    # Derive /tmp/litellm-proxy.env from the shared opencode-keys secret.
    # The secret is decrypted by home-manager's agenix module into
    # $HOME/.ssh/agenix_<user>. On nicky's host, that's
    # $HOME/.ssh/agenix_opencode_keys.env (the secret name from
    # users/opencode.nix).
    systemd.user.services.litellm-proxy-derive-keys = {
      description = "Derive LiteLLM proxy key environment from opencode-keys secret";
      after = [ "default.target" ];
      wantedBy = [ "default.target" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = "${deriveKeysEnv}/bin/litellm-proxy-derive-keys";
      };
    };

    # Writable, pre-restructured copy of the packaged admin UI.
    systemd.user.services.litellm-proxy-ui = {
      description = "Prepare writable, pre-restructured LiteLLM admin UI";
      after = [ "default.target" "litellm-proxy-derive-keys.service" ];
      before = [ "litellm-proxy.service" ];
      wantedBy = [ "default.target" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = prepareUi;
      };
      path = [ pkgs.coreutils pkgs.findutils ];
    };

    # The proxy itself.
    systemd.user.services.litellm-proxy = {
      description = "LiteLLM proxy — rank gateway for the local + paid LLM backends";
      after = [
        "network-online.target"
        "litellm-proxy-derive-keys.service"
        "litellm-proxy-ui.service"
      ];
      requires = [
        "litellm-proxy-derive-keys.service"
        "litellm-proxy-ui.service"
      ];
      wants = [ "network-online.target" ];
      serviceConfig = {
        Type = "simple";
        ExecStart =
          "${pkgs.litellm}/bin/litellm --config ${pkgs.writeText "litellm-config.yaml" proxyConfig} "
          + "--host 0.0.0.0 --port ${toString cfg.port}";
        EnvironmentFile = "/tmp/litellm-proxy.env";
        Environment = [
          # Prisma CLI cache (unused without --use_prisma_db_push, but present
          # for compatibility).
          "PRISMA_BINARY_CACHE_DIR=${prismaCli}"
          "PRISMA_ENGINES_CHECKSUM_IGNORE_MISSING=1"
        ];
        TimeoutStartSec = "300s";
        TimeoutStopSec = "20s";
        Restart = "always";
        RestartSec = 5;
      };
      wantedBy = [ "default.target" ];
    };
  };
}
