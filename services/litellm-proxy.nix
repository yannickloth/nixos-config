# LiteLLM proxy — the rank gateway in front of every LLM backend.
#
# One OpenAI-compatible endpoint (server-nike:4000) for opencode, pi and any
# other agent client on every host (laptop-p16 included), reached over
# Tailscale. server-nike hosts the proxy next to Unsloth Studio (loopback)
# and one Tailscale hop away from Strata on laptop-p16. Model names are the
# ranks from docs/ai-ranks.md (the ladder) plus the plain model ids of the
# unranked pool. The design, and the doc-grounded reason for every knob,
# lives in docs/litellm-proxy-design.md.
#
# Secrets: the proxy's master key and all backend keys are entries in the
# existing OPENAI_API_KEYS agenix secret (/etc/secrets/opencode-keys.env,
# see services/secrets.nix). litellm-proxy-env.service derives
# /run/litellm-proxy.env (LITELLM_* variables) from it at every start, so a
# key rotation is picked up without a second secret. The same secret entry
# is what opencode's setupOpenCodeKeys materializes as
# ~/.config/opencode/keys/litellm-proxy.key, so client and gateway always
# agree on the master key.
#
# Deploy: enabled on server-nike only (hosts/server-nike/server-nike.nix).
# The host firewall exposes tcp 4000 to the private ranges (LAN + tailnet)
# via lib.privateNetRules.

{ config, lib, pkgs, ... }:

let
  cfg = config.services.litellm-proxy;

  # Derives /run/litellm-proxy.env from the shared opencode-keys secret.
  # Runs as root (systemd oneshot); the target is 0600 root so only the
  # proxy service can read the backend keys. systemd's EnvironmentFile=
  # exports every var, and LiteLLM resolves `os.environ/VAR` in config.yaml.
  deriveKeysEnv = ''
    import json, os, sys

    SRC = "/etc/secrets/opencode-keys.env"
    DST = "/run/litellm-proxy.env"

    # env var -> base URL under which the key is stored in the secret
    # (the secret maps base URLs to keys; see secrets-README.md).
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

    fd = os.open(DST, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "w") as out:
        out.write("\n".join(lines) + "\n")
    print(f"litellm-proxy: wrote {DST} ({len(lines)} keys)")
  '';

  # The proxy configuration. Rationale for every section:
  # docs/litellm-proxy-design.md ("The configuration" + doc references).
  proxyConfig = ''
    # =============================================================================
    # LiteLLM proxy — rank gateway (server-nike:4000)
    #
    # - One model_name = one rank. Same-named deployments are ordered by
    #   litellm_params.order (lower = tried first); the router retries within a
    #   tier, then fails over to the next tier, then to cross-rank fallbacks.
    # - A 429 puts a deployment on a 5s cooldown immediately and promotes the
    #   next order tier mid-retry, so a quota-exhausted subscription costs at
    #   most one probe per cycle.
    # - Local + subscription deployments are explicitly zero-cost: spend
    #   tracking still logs tokens/latency/model_group, and budget checks
    #   treat the rank ladder as free (it is: hardware + subscriptions).
    # - Keys: os.environ/LITELLM_* (exported by EnvironmentFile from the shared
    #   agenix secret; see services/litellm-proxy.nix).
    # =============================================================================

    model_list:

      # ---------------------------------------------------------------------------
      # RANK LADDER (standing stack: local + subscription)
      # ---------------------------------------------------------------------------

      # Sergeant (OR-4) — fast, faithful executor (Unsloth Studio, co-located
      # with the proxy on server-nike -> loopback)
      - model_name: "sergeant"
        litellm_params:
          model: openai/unsloth/NVIDIA-Nemotron-3.5-Bolt-E4B-GGUF
          api_base: http://127.0.0.1:8888/v1
          api_key: os.environ/LITELLM_UNSLOTH_API_KEY
          temperature: 0.1        # deterministic execution
          timeout: 120
          stream_timeout: 30      # fast model: abort early, retry/fail fast
          num_retries: 1          # local: one retry, then move on
        model_info:
          id: sergeant-studio
          max_input_tokens: 128256
          supports_vision: false  # image requests are filtered out pre-call
          input_cost_per_token: 0
          output_cost_per_token: 0

      # Warrant Officer (OR-8) — Qwen3.6-35B-A3B: one rank, two deployments.
      # order 1 = Unsloth Studio (primary, co-located -> loopback),
      # order 2 = Hetzner free cloud (redundant). Order-based failover
      # instead of ad-hoc weights.
      - model_name: "warrant-officer"
        litellm_params:
          model: openai/unsloth/Qwen3.6-35B-A3B-MTP-GGUF
          api_base: http://127.0.0.1:8888/v1
          api_key: os.environ/LITELLM_UNSLOTH_API_KEY
          order: 1
          timeout: 300
          stream_timeout: 60
          num_retries: 1
        model_info:
          id: warrant-officer-studio
          max_input_tokens: 131072
          supports_vision: false
          input_cost_per_token: 0
          output_cost_per_token: 0
      - model_name: "warrant-officer"
        litellm_params:
          model: openai/Qwen/Qwen3.6-35B-A3B-FP8
          api_base: https://inference.hetzner.com/v1
          api_key: os.environ/LITELLM_HETZNER_API_KEY
          order: 2
          timeout: 300
          stream_timeout: 60
          num_retries: 2
        model_info:
          id: warrant-officer-hetzner
          max_input_tokens: 262144
          supports_vision: false
          input_cost_per_token: 0
          output_cost_per_token: 0

      # Second Lieutenant (OF-1a) — Qwen3.8-27B (Swift 1.5's base), free cloud
      - model_name: "second-lieutenant"
        litellm_params:
          model: openai/Qwen3.8-27B
          api_base: https://inference.hetzner.com/v1
          api_key: os.environ/LITELLM_HETZNER_API_KEY
          timeout: 600
          stream_timeout: 120
          num_retries: 2
        model_info:
          id: second-lieutenant-hetzner
          max_input_tokens: 262144
          supports_vision: false
          input_cost_per_token: 0
          output_cost_per_token: 0

      # Lieutenant (OF-1b) — Swift 1.5 on Strata (laptop-p16, one Tailscale
      # hop from the proxy). The default model.
      # max_parallel_requests: 1 — the engine is single-slot: a second
      # concurrent request gets a fast internal 429 and falls through to
      # second-lieutenant instead of queueing behind a long reasoning turn
      # (the documented "delegates to lower ranks when busy" behavior).
      - model_name: "lieutenant"
        litellm_params:
          model: openai/swift-1.5-iq3_xxs
          api_base: http://laptop-p16.bee-blues.ts.net:8080/v1
          api_key: strata            # Strata accepts any key
          timeout: 600
          stream_timeout: 180
          num_retries: 1
          max_parallel_requests: 1
        model_info:
          id: lieutenant-strata
          max_input_tokens: 393216
          supports_vision: false
          input_cost_per_token: 0
          output_cost_per_token: 0

      # Major (OF-4) — Kimi K2.8 Preview: previous generation, explicit
      # selection only (no auto-fallback in or out).
      - model_name: "major"
        litellm_params:
          model: openai/kimi-for-coding
          api_base: https://api.kimi.com/coding/v1
          api_key: os.environ/LITELLM_KIMI_API_KEY
          timeout: 600
          stream_timeout: 120
          num_retries: 2
        model_info:
          id: major-kimi
          max_input_tokens: 1048576

      # Lieutenant Colonel (OF-5, text) — GLM-5.3 @ Z.ai Coding Plan
      - model_name: "lieutenant-colonel"
        litellm_params:
          model: openai/glm-5.3
          api_base: https://api.z.ai/api/coding/paas/v4
          api_key: os.environ/LITELLM_ZAI_API_KEY
          timeout: 600
          stream_timeout: 120
          num_retries: 2
        model_info:
          id: lieutenant-colonel-zai
          max_input_tokens: 1000000
          supports_vision: false
          input_cost_per_token: 0
          output_cost_per_token: 0
          # Subscription: quota, not tokens. Off-peak quota window (for
          # planning, not tracking): weekends + Mon-Fri 06:00-10:00 UTC
          # (14:00-18:00 SGT) at 50% credits.

      # Lieutenant Colonel-v (OF-5, multimodal) — the rank's vision-capable
      # deployments, cost-ordered (cheapest quota first):
      #   order 1 k3-256k       K3, 262K window, ~half the quota of k3
      #   order 2 k3            K3, 1M window
      #   order 3 glm-5.3-flash 3x quota, weaker model — last intra-rank resort
      # The pre-call context check skips k3-256k automatically for prompts
      # above 262K.
      - model_name: "lieutenant-colonel-v"
        litellm_params:
          model: openai/k3-256k
          api_base: https://api.kimi.com/coding/v1
          api_key: os.environ/LITELLM_KIMI_API_KEY
          order: 1
          timeout: 600
          stream_timeout: 120
          num_retries: 2
        model_info:
          id: lc-v-k3-256k
          max_input_tokens: 262144
          input_cost_per_token: 0
          output_cost_per_token: 0
      - model_name: "lieutenant-colonel-v"
        litellm_params:
          model: openai/k3
          api_base: https://api.kimi.com/coding/v1
          api_key: os.environ/LITELLM_KIMI_API_KEY
          order: 2
          timeout: 600
          stream_timeout: 120
          num_retries: 2
        model_info:
          id: lc-v-k3
          max_input_tokens: 1048576
          input_cost_per_token: 0
          output_cost_per_token: 0
      - model_name: "lieutenant-colonel-v"
        litellm_params:
          model: openai/glm-5.3-flash
          api_base: https://api.z.ai/api/coding/paas/v4
          api_key: os.environ/LITELLM_ZAI_API_KEY
          order: 3
          timeout: 600
          stream_timeout: 120
          num_retries: 2
        model_info:
          id: lc-v-glm-flash
          max_input_tokens: 1000000
          input_cost_per_token: 0
          output_cost_per_token: 0

      # ---------------------------------------------------------------------------
      # UNRANKED — named by model id (pay-as-you-go pool, explicit selection)
      # ---------------------------------------------------------------------------
      # Cost-tracked: these are real money. LiteLLM looks up pricing in its
      # cost map by `litellm_provider / model_name`; where the cost map has the
      # upstream row (DeepSeek direct `deepseek/...`, CI `openai/gpt-5.6-luna`)
      # we let it. Where it does not (the other CI rows), pricing is pinned to
      # zero with a TODO until the actual discounted rates are known.

      # DeepSeek direct (pay-per-token). Off-peak = 50% outside the peak
      # windows 01:00-04:00 + 06:00-10:00 UTC, i.e. the complement windows
      # 04:00-06:00 and 10:00-01:00 — uncomment and fill the rates (standard
      # x 0.5) from the DeepSeek price sheet to track that discount:
      #   model_info:
      #     off_peak_pricing:
      #       hours_utc: ["04:00-06:00", "10:00-01:00"]
      #       input_cost_per_token: ...
      #       output_cost_per_token: ...
      - model_name: "deepseek-flash"
        litellm_params:
          model: deepseek/deepseek-flash
          api_key: os.environ/LITELLM_DEEPSEEK_API_KEY
          timeout: 600
          stream_timeout: 120
        model_info:
          id: deepseek-flash-direct
          max_input_tokens: 1000000

      - model_name: "deepseek-v4-pro"
        litellm_params:
          model: deepseek/deepseek-v4-pro
          api_key: os.environ/LITELLM_DEEPSEEK_API_KEY
          timeout: 600
          stream_timeout: 120
        model_info:
          id: deepseek-v4-pro-direct
          max_input_tokens: 1000000
          supports_vision: false

      # CheaperInference (wallet-backed reseller, ci_live_ keys)
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
          # TODO: fill CI discounted rates once known; cost map has no row.
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
          # TODO: fill CI discounted rates once known; cost map has no row.
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
          # TODO: fill CI discounted rates once known; cost map has no row.
          input_cost_per_token: 0
          output_cost_per_token: 0

      # GLM-5.3 on the pay-per-token catalog (the Coding Plan's GLM-5.3 is the
      # lieutenant-colonel rank; this row is the per-token twin, 1M output)
      - model_name: "glm-5.3"
        litellm_params:
          model: openai/glm-5.3
          api_base: https://api.cheaperinference.com/v1
          api_key: os.environ/LITELLM_CHEAPERINFERENCE_API_KEY
          timeout: 600
          stream_timeout: 120
        model_info:
          id: glm-5.3-ci
          max_input_tokens: 1000000
          supports_vision: false
          # TODO: fill CI discounted rates once known; cost map has no row.
          input_cost_per_token: 0
          output_cost_per_token: 0


    # -----------------------------------------------------------------------------
    # Router
    # -----------------------------------------------------------------------------
    router_settings:
      # simple-shuffle (the recommended default): random pick within the
      # current order tier. No rpm/tpm/weight anywhere, so order is a pure
      # priority: local primary, redundant/cheaper tiers behind it.
      routing_strategy: simple-shuffle

      # LiteLLM's own retry loop. `max_retries` in a request is IGNORED by the
      # proxy (the provider SDK is pinned to 0 to avoid double retries).
      # Precedence: x-litellm-num-retries header > request body > deployment
      # > this default.
      num_retries: 2

      # Park a failing deployment quickly: one failure puts it in a 5s
      # cooldown, so a quota-exhausted subscription costs at most one probe per
      # cycle and the next order tier is promoted mid-retry.
      allowed_fails: 1
      cooldown_time: 5

      # Pre-call checks: drop deployments whose max_input_tokens is below the
      # prompt length before calling them (long-context requests skip
      # k3-256k and the 10K studio copy without burning a provider call).
      enable_pre_call_checks: true

      # Session affinity: pin a conversation to the deployment that served its
      # first request (x-litellm-session-id / x-<vendor>-session-id header or
      # metadata.session_id) — keeps provider prompt caches (Z.ai, Kimi) warm.
      # No-op for clients that send no session id; a cooled-down pin falls
      # through to the healthy deployments and is kept for when it recovers.
      optional_pre_call_checks:
        - session_affinity

      # Cross-rank fallbacks — the local cascade only. Paid ranks are explicit
      # selections: no auto-fallback between them (silent cost escalation, and
      # cycles are unreliable in LiteLLM).
      fallbacks:
        - lieutenant: [second-lieutenant, warrant-officer, sergeant]
        - second-lieutenant: [warrant-officer, sergeant]
        - warrant-officer: [sergeant]

      # The cascade is at most three hops.
      max_fallbacks: 3

    litellm_settings:
      # Local GGUF backends reject parameters they don't know; drop them
      # instead of failing the request.
      drop_params: true
      # Proxy-wide default for deployments without their own timeout.
      request_timeout: 600

    general_settings:
      # Single master key for all clients. No virtual keys / postgres: budgets
      # and per-key model allowlists would need a DATABASE_URL — a documented
      # upgrade path, not a current requirement (see the design doc).
      master_key: os.environ/LITELLM_MASTER_KEY
  '';
in
{
  options.services.litellm-proxy = {
    enable = lib.mkEnableOption "LiteLLM proxy (rank gateway for the local + paid LLM backends)";
    port = lib.mkOption {
      type = lib.types.port;
      default = 4000;
      description = "TCP port the proxy listens on (all interfaces; the host firewall scopes it to the private ranges).";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.etc = {
      "litellm/config.yaml".text = proxyConfig;
      "litellm/derive-keys-env.py".text = deriveKeysEnv;
    };

    systemd.services = {
      # Derives /run/litellm-proxy.env from the agenix-decrypted key secret.
      # Runs before the proxy on every boot/switch; a key rotation changes
      # this unit's start order target, and the proxy's PartOf= below makes it
      # restart when the env is re-derived.
      litellm-proxy-env = {
        description = "Derive LiteLLM proxy key environment from /etc/secrets/opencode-keys.env";
        after = [ "agenix-install-secrets.service" ];
        wants = [ "agenix-install-secrets.service" ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          ExecStart = "${pkgs.python3}/bin/python3 /etc/litellm/derive-keys-env.py";
        };
        wantedBy = [ "multi-user.target" ];
      };

      litellm-proxy = {
        description = "LiteLLM proxy — rank gateway for the local + paid LLM backends";
        after = [ "network-online.target" "tailscale.service" "litellm-proxy-env.service" ];
        wants = [ "tailscale.service" "litellm-proxy-env.service" ];
        serviceConfig = {
          ExecStart =
            "${pkgs.litellm}/bin/litellm --config /etc/litellm/config.yaml "
            + "--host 0.0.0.0 --port ${toString cfg.port}";
          # systemd exports every LITELLM_* key to the proxy process; the
          # config references them through LiteLLM's os.environ/ resolver.
          EnvironmentFile = "/run/litellm-proxy.env";
          # Persistent SQLite spend log (/spend/logs, /user/daily/activity).
          StateDirectory = "litellm";
          WorkingDirectory = "/var/lib/litellm";
          PartOf = [ "litellm-proxy-env.service" ];
          Restart = "always";
          RestartSec = 5;
        };
        wantedBy = [ "multi-user.target" ];
      };
    };
  };
}
