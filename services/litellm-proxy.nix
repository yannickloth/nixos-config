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
# see services/secrets.nix). The PostgreSQL role password is the separate
# litellm-db-password secret. litellm-proxy-env.service derives
# /run/litellm-proxy.env (LITELLM_* variables + DATABASE_URL) from both at
# every start, so a rotation is picked up without rebuilding. The same master
# key entry is what opencode's setupOpenCodeKeys materializes as
# ~/.config/opencode/keys/litellm-proxy.key, so client and gateway always
# agree.
#
# Deploy: enabled on server-nike only (hosts/server-nike/server-nike.nix).
# The host firewall exposes tcp 4000 to the private ranges (LAN + tailnet)
# via lib.privateNetRules.

{ config, lib, pkgs, ... }:

let
  cfg = config.services.litellm-proxy;

  # LiteLLM's Python Prisma client is generated from the schema shipped in
  # pkgs.litellm. nixpkgs does not run `prisma generate`, so do it at build time
  # in a writable copy of the prisma Python package. The generated package is
  # put first on PYTHONPATH by the proxy service.
  prismaPython = pkgs.runCommand "litellm-prisma-python" {
    nativeBuildInputs = [
      pkgs.nodejs
      pkgs.openssl
      pkgs.prisma_6
      pkgs.python3Packages.prisma
    ];
  } ''
    mkdir -p $out
    cp -a ${pkgs.python3Packages.prisma}/lib/python3.13/site-packages/prisma $out/prisma
    chmod -R u+w $out/prisma
    cp ${pkgs.litellm}/lib/python3.13/site-packages/litellm/proxy/schema.prisma ./schema.prisma
    export PYTHONPATH=$out
    export PRISMA_PY_DEBUG_GENERATOR=1
    export PATH=${pkgs.prisma_6}/bin:${pkgs.python3Packages.prisma}/bin:${pkgs.nodejs}/bin:$PATH
    prisma generate --schema ./schema.prisma
    rm -f $out/prisma/generator/debug-*.json
    find $out/prisma -name __pycache__ -type d -prune -exec rm -rf {} +
  '';

  # Read-only Prisma CLI cache for LiteLLM's runtime `prisma db push` and
  # `prisma migrate diff` calls. All engines are supplied via environment
  # variables, so the CLI never downloads or writes into its package tree.
  prismaCli = pkgs.runCommand "litellm-prisma-cli" { } ''
    mkdir -p $out/cache/node_modules
    ln -s ${pkgs.prisma_6}/lib/prisma/packages $out/packages
    ln -s $out/packages/cli $out/cache/node_modules/prisma
    echo '{"name":"prisma-binaries","version":"1.0.0","private":true,"main":"node_modules/prisma/build/index.js"}' > $out/cache/package.json
  '';

  # LiteLLM's packaged UI is read-only in the Nix store, and its own
  # copytree preserves that mode, so the extensionless route restructure
  # (`login.html` -> `login/index.html`) is skipped. Build a writable,
  # pre-restructured copy once and point LITELLM_UI_PATH at it.
  prepareUi = pkgs.writeShellScript "litellm-prepare-ui" ''
    set -euo pipefail

    UI=/var/lib/litellm/ui
    SRC=${pkgs.litellm}/lib/python3.13/site-packages/litellm/proxy/_experimental/out

    if [ -f "$UI/.litellm_ui_ready" ] && [ "$(cat "$UI/.litellm_source" 2>/dev/null || true)" = "$SRC" ]; then
      exit 0
    fi

    rm -rf "$UI"
    mkdir -p "$UI"
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

  # Derives /run/litellm-proxy.env from the shared opencode-keys secret plus
  # the LiteLLM database password. Runs as root (systemd oneshot); the target
  # is 0600 root so only the proxy service can read the backend keys.
  # systemd's EnvironmentFile= exports every var, and LiteLLM resolves
  # `os.environ/VAR` in config.yaml.
  deriveKeysEnv = ''
    import json, os, sys

    SRC = "/etc/secrets/opencode-keys.env"
    DST = "/run/litellm-proxy.env"
    DB_PW_FILE = "/run/agenix/litellm-db-password"

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

    try:
        with open(DB_PW_FILE) as fh:
            db_pw = fh.read().strip()
    except FileNotFoundError:
        print(f"litellm-proxy: {DB_PW_FILE} is missing - is agenix activated?", file=sys.stderr)
        sys.exit(1)
    if not db_pw:
        print(f"litellm-proxy: {DB_PW_FILE} is empty", file=sys.stderr)
        sys.exit(1)
    lines.append(
        f"DATABASE_URL=postgresql://litellm:{db_pw}@127.0.0.1:5432/litellm"
    )

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
        after = [ "agenix.service" ];
        wants = [ "agenix.service" ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          Restart = "on-failure";
          RestartSec = 5;
          ExecStart = "${pkgs.python3}/bin/python3 /etc/litellm/derive-keys-env.py";
        };
        wantedBy = [ "multi-user.target" ];
      };

      # Writable, pre-restructured copy of the packaged admin UI. Runs before
      # the proxy so LITELLM_UI_PATH is ready and extensionless routes work.
      litellm-proxy-ui = {
        description = "Prepare writable, pre-restructured LiteLLM admin UI";
        after = [ "local-fs.target" ];
        before = [ "litellm-proxy.service" ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          StateDirectory = "litellm";
          ExecStart = prepareUi;
        };
        path = [ pkgs.coreutils pkgs.findutils ];
        wantedBy = [ "multi-user.target" ];
      };

      litellm-proxy = {
        description = "LiteLLM proxy — rank gateway for the local + paid LLM backends";
        after = [
          "network-online.target"
          "tailscale.service"
          "litellm-proxy-env.service"
          "litellm-proxy-ui.service"
          "postgresql.service"
        ];
        requires = [
          "litellm-proxy-env.service"
          "litellm-proxy-ui.service"
          "postgresql.service"
        ];
        wants = [
          "network-online.target"
          "tailscale.service"
        ];
        # Prisma needs Node to run the cached CLI, OpenSSL to detect the
        # platform, and the prisma package for the generated Python client.
        path = [
          pkgs.nodejs
          pkgs.openssl
          pkgs.prisma_6
          pkgs.python3Packages.prisma
        ];
        serviceConfig = {
          ExecStart =
            "${pkgs.litellm}/bin/litellm --config /etc/litellm/config.yaml "
            + "--host 0.0.0.0 --port ${toString cfg.port} "
            + "--use_prisma_db_push";
          Environment = [
            # Writable UI copy: LiteLLM restructures exported HTML routes
            # (e.g. login.html -> login/index.html) on first start.
            "LITELLM_UI_PATH=/var/lib/litellm/ui"
            # Prisma CLI cache built above; all engines are explicit so the
            # CLI never downloads or writes into the read-only Nix store.
            "PRISMA_BINARY_CACHE_DIR=${prismaCli}/cache"
            "PRISMA_QUERY_ENGINE_BINARY=${pkgs.prisma-engines_6}/bin/query-engine"
            "PRISMA_QUERY_ENGINE_LIBRARY=${pkgs.prisma-engines_6}/lib/libquery_engine.node"
            "PRISMA_SCHEMA_ENGINE_BINARY=${pkgs.prisma-engines_6}/bin/schema-engine"
            "PRISMA_ENGINES_CHECKSUM_IGNORE_MISSING=1"
            # LiteLLM's Python client expects Prisma 5.17.0; Prisma 6 engines
            # are protocol-compatible and the generated client is tested.
            "PRISMA_PY_DEBUG_GENERATOR=1"
            # Generated Python client goes before the ungenerated package.
            "PYTHONPATH=${prismaPython}"
          ];
          # systemd exports every LITELLM_* / DATABASE_URL value to the proxy
          # process; the config references the keys via os.environ/.
          EnvironmentFile = "/run/litellm-proxy.env";
          # Persistent spend log + writable UI copy.
          StateDirectory = "litellm";
          WorkingDirectory = "/var/lib/litellm";
          PartOf = [ "litellm-proxy-env.service" ];
          # First start runs `prisma db push` over the full schema; later
          # starts are fast. Keep systemd from killing the migration.
          TimeoutStartSec = "300s";
          Restart = "always";
          RestartSec = 5;
        };
        wantedBy = [ "multi-user.target" ];
      };
    };
  };
}
