# LiteLLM proxy — the rank gateway in front of every LLM backend.
#
# One OpenAI-compatible endpoint (server-nike:4000) for opencode, pi and any
# other agent client on every host (laptop-p16 included), reached over
# Tailscale. server-nike hosts the proxy next to the local Strata engine
# (loopback) and one Tailscale hop away from Strata on laptop-p16. Three classes
# of model name:
#   - the rank ladder of docs/ai-ranks.md. Every model of every ranked provider
#     — Z.ai Coding Plan, Kimi Code (legacy Allegretto plan), DeepSeek API,
#     Hetzner Inference — plus the two local models (Swift 1.5 on Strata,
#     Nemotron on Studio) holds a rank slot, so a model swap never needs a
#     client-config change;
#   - one explicit name per ranked model, spelled exactly like the upstream id
#     (k3.1-pro, glm-5.3-flash, deepseek-flash, the four Hetzner ids, ...), for
#     callers that want the model itself rather than a rank;
#   - the unranked pay-as-you-go pool: CheaperInference only (the ladder does
#     not cover its OpenAI/Anthropic models) plus glm-5.3-payg, the cash twin
#     of the Coding Plan's glm-5.3.
# The design, and the doc-grounded reason for every knob, lives in
# docs/litellm-proxy-design.md.
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
    # LITELLM_UNSLOTH_API_KEY backs sergeant's order-2 tier (Studio Nemotron),
    # used only when the resident Strata engine cannot answer.
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
    # - One model_name = one rank, or one explicit model id of a ranked model.
    #   Same-named deployments are ordered by litellm_params.order (lower =
    #   tried first): subscription -> pay-per-token -> free cloud -> local. The
    #   router retries within a tier, then fails over to the next tier, then to
    #   cross-rank fallbacks (free ranks only).
    # - A 429 puts a deployment on a 5s cooldown immediately and promotes the
    #   next order tier mid-retry, so a quota-exhausted subscription costs at
    #   most one probe per cycle.
    # - Local, free-cloud and subscription deployments are explicitly zero-cost:
    #   spend tracking still logs tokens/latency/model_group, and budget checks
    #   treat quota as free (it is: hardware + subscriptions). The DeepSeek rows
    #   behind captain / captain-commandant / major are priced by the cost map;
    #   CheaperInference rows are pinned to zero with a TODO.
    # - Keys: os.environ/LITELLM_* (exported by EnvironmentFile from the shared
    #   agenix secret; see services/litellm-proxy.nix).
    # =============================================================================

    model_list:

      # ===========================================================================
      # RANK LADDER
      #
      # Every model of the ranked providers — Z.ai Coding Plan, Kimi Code (legacy
      # Allegretto plan), DeepSeek API, Hetzner Inference — plus the two local
      # models (Swift 1.5 on Strata, Nemotron on Studio) holds a rank slot;
      # docs/ai-ranks.md carries the mapping and its evidence. Two rules govern
      # the ladder:
      #   - Intra-rank deployment order (litellm_params.order, lowest first):
      #     subscription quota -> pay-per-token API -> free cloud -> local.
      #     A quota-exhausted subscription falls to the next tier, never the
      #     other way round.
      #   - Anything paid is an explicit selection: no cross-rank fallback in or
      #     out of a paid rank (auto-escalation of cost is worse than a visible
      #     error). The auto cascade stays inside the free stack.
      #
      # Plain ranks are text-only by contract even when their model is
      # multimodal; the vision slot is the -v sibling, and every deployment
      # behind a -v name is itself image-capable.
      # ===========================================================================

      # ---------------------------------------------------------------------------
      # Standing stack (local + free cloud): the auto-fallback ladder
      #
      # The local tiers all point at the Strata engine on server-nike. Reason:
      # this host cannot hold more than one model in VRAM at a time, and every
      # swap costs a full load (~30 s) plus the decode rate the card pays while
      # it streams weights. One resident Strata model keeps the GPU warm across
      # ranks; Studio GGUF copies are used only where nothing else can answer.
      # ---------------------------------------------------------------------------

      # Sergeant (OR-4) — fast executor. Local first: the Strata engine
      # co-located with the proxy (server-nike:8080, loopback), the same
      # resident weights as warrant-officer's local fallback.
      # order 1 = Strata swift-1.5-iq3_xxs (256K ctx) — no model load
      # order 2 = Unsloth Studio Nemotron (128K ctx) — only when Strata is
      #           absent; this tier costs one model load, which is why it sits
      #           behind the resident engine.
      # max_parallel_requests: 1 on the Strata tier — the engine is single-slot:
      # a second concurrent request gets a fast 429 instead of queueing behind
      # a long turn.
      # stream_timeout: 120 on the Strata tier — the first token waits for a
      # possible engine load (~30 s) after idleUnloadSeconds; after the first
      # token the stream must keep moving.
      - model_name: "sergeant"
        litellm_params:
          model: openai/swift-1.5-iq3_xxs
          api_base: http://127.0.0.1:8080/v1
          api_key: strata            # Strata accepts any key
          temperature: 0.1        # deterministic execution
          order: 1
          timeout: 300
          stream_timeout: 120
          num_retries: 1          # local: one retry, then move on
          max_parallel_requests: 1
        model_info:
          id: sergeant-strata
          # The window the nike engine serves: `strata launch` writes
          # --max-context 262144, and live GET :8080/v1/models reports
          # n_ctx 262144. The model's native window is 384K.
          max_input_tokens: 262144
          supports_vision: false  # text rank: clients are not wired to send
                                 # images here (no attachment flag)
          input_cost_per_token: 0
          output_cost_per_token: 0
      - model_name: "sergeant"
        litellm_params:
          model: openai/unsloth/NVIDIA-Nemotron-3.5-Bolt-E4B-GGUF
          api_base: http://127.0.0.1:8888/v1
          api_key: os.environ/LITELLM_UNSLOTH_API_KEY
          temperature: 0.1        # deterministic execution
          order: 2
          timeout: 120
          stream_timeout: 30      # fast model: abort early, retry/fail fast
          num_retries: 1
        model_info:
          id: sergeant-studio
          max_input_tokens: 128256
          supports_vision: false  # text rank
          input_cost_per_token: 0
          output_cost_per_token: 0

      # Warrant Officer (OR-8) — Qwen3.6-35B-A3B on Hetzner, with the resident
      # Strata engine co-located with the proxy as the fallback. No Unsloth
      # Studio deployment: one resident local model, and a cloud outage must not
      # swap in (and later swap out) a second set of weights.
      # order 1 = Hetzner free cloud (FP8, 262K ctx) — default: no local model
      #           load, and the GPU stays free for the Strata engine,
      # order 2 = Strata on server-nike (swift-1.5-iq3_xxs, 256K ctx).
      # The two orders serve different models; the rank is the workhorse slot,
      # not a single-model pair.
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
          supports_vision: false  # text rank; images route via warrant-officer-v
          input_cost_per_token: 0
          output_cost_per_token: 0
      - model_name: "warrant-officer"
        litellm_params:
          model: openai/swift-1.5-iq3_xxs
          api_base: http://127.0.0.1:8080/v1
          api_key: strata            # Strata accepts any key
          order: 2
          timeout: 600
          stream_timeout: 180
          num_retries: 1
          max_parallel_requests: 1
        model_info:
          id: warrant-officer-strata
          max_input_tokens: 262144   # served window on nike (live n_ctx)
          supports_vision: false  # text rank: contract, not capability — the
                                  # model does see images (live GET /v1/models:
                                  # input_modalities text+image); images are
                                  # addressed to warrant-officer-v
          input_cost_per_token: 0
          output_cost_per_token: 0

      # Warrant Officer (vision) — same two deployments as warrant-officer: the
      # Hetzner FP8 copy (natively multimodal, verified) and the local Strata
      # Swift 1.5 fallback. The -v suffix exposes the vision slot, keeping the
      # text rank text-only.
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
          api_base: http://127.0.0.1:8080/v1
          api_key: strata            # Strata accepts any key
          order: 2
          timeout: 600
          stream_timeout: 180
          num_retries: 1
          max_parallel_requests: 1
        model_info:
          id: warrant-officer-v-strata
          max_input_tokens: 262144   # served window on nike (live n_ctx)
          supports_vision: true    # verified: live GET /v1/models reports
                                   # input_modalities text+image, and the same
                                   # weights served the lieutenant-v pixel tests
          input_cost_per_token: 0
          output_cost_per_token: 0

      # Second Lieutenant (OF-1a) — Qwen3.8-27B (Swift 1.5's base), free cloud,
      # with the resident Strata engine on server-nike as fallback.
      # order 1 = Hetzner free cloud (256K ctx)
      # order 2 = Strata swift-1.5-iq3_xxs on server-nike (256K ctx) — the
      #           same resident weights as sergeant and warrant-officer's local
      #           fallback, so the fallback needs no model load. Both orders
      #           hold the same window, so the context check never picks one.
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
          api_base: http://127.0.0.1:8080/v1
          api_key: strata            # Strata accepts any key
          order: 2
          timeout: 600
          stream_timeout: 180
          num_retries: 1
          max_parallel_requests: 1
        model_info:
          id: second-lieutenant-strata
          max_input_tokens: 262144   # served window on nike (live n_ctx)
          supports_vision: false  # text rank; the local model does see images,
                                  # but images are addressed to -v ranks only
          input_cost_per_token: 0
          output_cost_per_token: 0

      # Lieutenant (OF-1b) — Swift 1.5 on Strata (laptop-p16, one Tailscale
      # hop from the proxy). The default model.
      # max_parallel_requests: 1 — the engine is single-slot: a second
      # concurrent request gets a fast internal 429 and falls through to
      # second-lieutenant instead of queueing behind a long reasoning turn
      # (the documented "delegates to lower ranks when busy" behavior).
      # 256K window: `strata launch` writes --max-context 262144 and the live
      # GET :8080/v1/models reports n_ctx 262144, so the local rank no longer
      # drops a long prompt early. A prompt above 262144 tokens has no local
      # or free-cloud deployment left in this ladder.
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
          # The window the Strata engine serves on laptop-p16: --max-context
          # 262144 in its run config, live GET :8080/v1/models -> n_ctx 262144.
          # The model's native window is 384K.
          max_input_tokens: 262144
          supports_vision: false  # text rank; images route via lieutenant-v
          input_cost_per_token: 0
          output_cost_per_token: 0

      # Lieutenant (vision) — SAME model as lieutenant (Swift 1.5 on Strata is
      # natively multimodal, verified by pixel-color tests); the -v suffix
      # exposes the vision slot.
      # max_parallel_requests is tracked per deployment (model_id), so
      # lieutenant and lieutenant-v each get one in-flight slot; LiteLLM never
      # cascades vision traffic into the text fallback chain because a text
      # session is in flight (or vice versa). Genuine engine contention on the
      # single-slot Strata instance is still answered by Strata itself (fast
      # 429 -> the router falls through to the next vision rank).
      - model_name: "lieutenant-v"
        litellm_params:
          model: openai/swift-1.5-iq3_xxs
          api_base: http://laptop-p16.bee-blues.ts.net:8080/v1
          api_key: strata            # Strata accepts any key
          timeout: 600
          stream_timeout: 180
          num_retries: 1
          max_parallel_requests: 1
        model_info:
          id: lieutenant-v-strata
          max_input_tokens: 262144   # same served window as lieutenant-strata
          supports_vision: true
          input_cost_per_token: 0
          output_cost_per_token: 0

      # ---------------------------------------------------------------------------
      # Paid ranks (explicit selection only, never an auto-fallback target)
      # ---------------------------------------------------------------------------

      # Captain (OF-2) — DeepSeek V4.1 Flash: the cheapest paid coder, above the
      # free stack on capability (1M ctx, 384K out, images). Pay-per-token:
      # priced by LiteLLM's cost map from the deepseek/ row (see the off-peak
      # note in the DeepSeek explicit block).
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
          supports_vision: false  # text rank; images route via captain-v

      # Captain (vision) — same model as captain: GET /v1/models reports
      # input_modalities [text, image] for deepseek-flash.
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

      # Captain Commandant (OF-3) — the mid paid coders, subscription first:
      #   order 1  glm-5-turbo     Z.ai Coding Plan (plan quota, 200K ctx)
      #   order 2  deepseek-v4-pro DeepSeek API (pay-per-token, 1.6T params,
      #                            hardest reasoning, best agentic knowledge)
      # No -v sibling: neither model takes images (Z.ai's vision line is the
      # glm-5.3-flash series; DeepSeek lists Vision "Not supported" for v4-pro).
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
          supports_vision: false  # model is text-only: no vision slot for this rank

      # Major (OF-4) — strong, not frontier. Subscription first, cash last:
      #   order 1  kimi-for-coding  Kimi (K2.8 Preview: performance close to K3,
      #                             1M ctx, the previous-generation flagship)
      #   order 2  glm-5.3-flash    Z.ai Coding Plan (native multimodal MoE, 1M
      #                             ctx, 3x the quota of glm-5.3, 18B active)
      #   order 3  deepseek-v4-pro  DeepSeek API (pay-per-token twin of the
      #                             rank's cash option)
      # glm-5.3-flash is a clear tier below glm-5.3, which is why it sits at
      # Major and not at Lieutenant Colonel. major stays text-only by contract
      # (plain rank): all of its deployments are image-capable — K2.8 per Kimi's
      # model table and the live /coding/v1/models metadata (supports_image_in:
      # true), the Z.ai row by spec — but images are addressed to major-v.
      #
      # Z.ai (official docs, 2026-11-21): GLM-5.3 / GLM-5.3-Flash always
      # reason — requests with thinking disabled are rejected, and
      # `reasoning_effort` (low/high/max, default max) selects the depth.
      # The docs recommend `max` for agent work, so every Z.ai GLM-5.3 /
      # GLM-5.3-Flash deployment in this file pins `reasoning_effort: max`.
      # The pay-per-token glm-5.3-payg row is deliberately left unpinned:
      # CheaperInference is a reseller endpoint with its own parameter
      # contract (unknown params pass through).
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
          supports_vision: false  # text rank by contract; the model IS
                                  # image-capable (see major-v)
          input_cost_per_token: 0
          output_cost_per_token: 0
      - model_name: "major"
        litellm_params:
          model: openai/glm-5.3-flash
          api_base: https://api.z.ai/api/coding/paas/v4
          api_key: os.environ/LITELLM_ZAI_API_KEY
          reasoning_effort: max   # Z.ai: thinking always on; docs recommend max
          order: 2
          timeout: 600
          stream_timeout: 120
          num_retries: 2
        model_info:
          id: major-zai
          max_input_tokens: 1000000
          supports_vision: false  # text rank: the model IS multimodal, images
                                  # are addressed to major-v
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

      # Major (vision) — the rank's image-capable deployments, stronger first:
      #   order 1  kimi-for-coding  K2.8 (Kimi; image+video per Kimi's model
      #                             table, supports_image_in: true in the live
      #                             GET /coding/v1/models, live pixel tests by
      #                             third parties answered correctly)
      #   order 2  glm-5.3-flash    Z.ai (the series' documented multimodal
      #                             line, 3x the quota — the quota fallback)
      # Format caveat (Kimi docs): image parts must be content-array image_url
      # entries with a base64 data URL; public image URLs are rejected
      # ("unsupported image url" 400).
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
          reasoning_effort: max   # Z.ai: thinking always on; docs recommend max
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

      # Lieutenant Colonel (OF-5) — the frontier tier, all subscription:
      #   order 1  glm-5.3   Z.ai Coding Plan (dense flagship, 1M ctx, text-only,
      #                       token-efficient per token vs Opus, SWE-bench 95.4)
      #   order 2  k3        Kimi (2.8T / 104B active, 1M ctx on Allegretto,
      #                       natively multimodal; ties GLM-5.3 on the
      #                       Intelligence Index, trails on SWE-bench 93.4 v 95.4)
      #   order 3  k3-256k   Kimi (same model, 262K window, ~half the quota)
      # The pre-call context check drops k3-256k above 262K and the Z.ai row
      # above 1M, so a long prompt lands on the deployment that can hold it.
      - model_name: "lieutenant-colonel"
        litellm_params:
          model: openai/glm-5.3
          api_base: https://api.z.ai/api/coding/paas/v4
          api_key: os.environ/LITELLM_ZAI_API_KEY
          reasoning_effort: max   # Z.ai: thinking always on; docs recommend max
          order: 1
          timeout: 600
          stream_timeout: 120
          num_retries: 2
        model_info:
          id: lieutenant-colonel-zai
          max_input_tokens: 1000000
          supports_vision: false  # GLM-5.3 is text-only by provider spec
          input_cost_per_token: 0
          output_cost_per_token: 0
          # Subscription: quota, not tokens. Off-peak quota window (for
          # planning, not tracking): weekends + Mon-Fri 06:00-10:00 UTC
          # (14:00-18:00 SGT) at 50% credits.
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
          supports_vision: false  # text rank; images route via -v
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

      # Lieutenant Colonel (vision) — the rank's image-capable deployments,
      # quota-ordered: k3 (1M, image+video per Kimi's model table) then
      # k3-256k (262K, image only, ~half the quota). glm-5.3 is absent:
      # text-only model.
      # Vision basis (docs/ai-ranks.md "Vision verification"): Kimi's model
      # table declares image input for the K3 line, the live
      # GET /coding/v1/models reports supports_image_in: true, and third-party
      # pixel tests against this endpoint (2026-09/11) answered correctly on
      # both wires. Format caveat: images must be content-array image_url
      # parts with a base64 data URL — public image URLs are rejected.
      # TODO(vision-verify): re-run the pixel test THROUGH the proxy to confirm
      # the LiteLLM passthrough preserves the image part.
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

      # Brigadier General (OF-6) — k3.1-pro @ Kimi: 3T-class flagship, the
      # strongest model in the stack. Thinking-only: the provider rejects
      # requests with thinking disabled, so reasoning_effort is pinned
      # proxy-side (the rank contract keeps provider parameters out of client
      # config). 1M context on Allegretto (legacy plan: 1M for Allegretto+).
      - model_name: "brigadier-general"
        litellm_params:
          model: openai/k3.1-pro
          api_base: https://api.kimi.com/coding/v1
          api_key: os.environ/LITELLM_KIMI_API_KEY
          reasoning_effort: high   # provider default; thinking cannot be off
          timeout: 600
          stream_timeout: 120
          num_retries: 2
        model_info:
          id: brigadier-general-kimi
          max_input_tokens: 1048576
          supports_vision: false
          input_cost_per_token: 0
          output_cost_per_token: 0

      # Brigadier General (vision) — same model; Kimi's model table declares
      # image+video input for the K3.1 Pro series, and the 2026-11-17 live test
      # of the K3.1 Pro line against this endpoint answered a solid-red PNG
      # correctly. Same format caveat and same TODO(vision-verify) (through
      # the proxy) as lieutenant-colonel-v.
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
      # EXPLICIT MODEL NAMES — one name per model, spelled exactly like the
      # upstream id, so a caller can ask for a specific model instead of a rank.
      # Each is a plain model id: asking for it means asking for that model, on
      # the provider named here. No cross-rank fallback in or out. The same
      # model served by several providers (glm-5.3 on the Coding Plan vs the
      # pay-per-token catalog) keeps separate names, so a name never hides a
      # cost class: the plan id draws subscription quota, the -payg id draws
      # cash.
      # ===========================================================================

      # Kimi Code (legacy Allegretto plan: every id below is entitled, and the
      # 1M context on k3.1-pro / k3 is Allegretto's 1M tier)
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
          supports_vision: true   # Kimi model table: image+video; live test
                                  # 2026-11-17 answered a red PNG correctly
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
          supports_vision: true   # Kimi model table: image+video; live pixel
                                  # tests 2026-09 answered correctly
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
          supports_vision: true   # Kimi model table: image only (no video),
                                  # live /v1/models: supports_image_in true
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
          supports_vision: true   # Kimi model table: image+video; live
                                  # /v1/models: supports_image_in true, and a
                                  # live pixel test on this id answered
                                  # correctly (supersedes the old repo finding
                                  # — see docs/ai-ranks.md)
          input_cost_per_token: 0
          output_cost_per_token: 0

      # Z.ai Coding Plan (subscription quota; the coding endpoint only — a plan
      # key is rejected on the pay-per-token endpoint)
      - model_name: "glm-5.3"
        litellm_params:
          model: openai/glm-5.3
          api_base: https://api.z.ai/api/coding/paas/v4
          api_key: os.environ/LITELLM_ZAI_API_KEY
          reasoning_effort: max   # Z.ai: thinking always on; docs recommend max
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
          reasoning_effort: max   # Z.ai: thinking always on; docs recommend max
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

      # DeepSeek API (pay-per-token). Off-peak = 50% outside the peak windows
      # 01:00-04:00 + 06:00-10:00 UTC, i.e. the complement windows 04:00-06:00
      # and 10:00-01:00 — uncomment and fill the rates (standard x 0.5) from the
      # DeepSeek price sheet to track that discount. The same rows back the
      # captain / captain-commandant / major ranks, so enable it once:
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

      # ---------------------------------------------------------------------------
      # HETZNER FREE CLOUD — the ladder's two Hetzner deployments, exposed under
      # their own upstream ids (explicit selection: one name = exactly one
      # deployment, no intra-name failover, no cross-rank fallback in or out)
      # ---------------------------------------------------------------------------
      # Official docs: the base URL is https://inference.hetzner.com/api/v1;
      # the 2026-11-21 live probe found BOTH /v1 (used here) and /api/v1
      # answering (401 without a key). Rate limits per key: 4M input / 100K
      # output tokens, 10 requests per 60s window. Free while the Inference
      # experiment runs.
      # GET https://inference.hetzner.com/v1/models answers four ids over two
      # serving deployments, every one of them max_model_len 262144: the 35B MoE
      # is served from the FP8 weights under both `Qwen/Qwen3.6-35B-A3B` and
      # `Qwen/Qwen3.6-35B-A3B-FP8`, and the dense 27B answers both
      # `Qwen/Qwen3.8-27B` and `Qwen3.8-27B`. Free tier -> zero cost, like the
      # ranks. The rank names keep their own routing: warrant-officer still
      # fails over to the local Strata engine, which these ids deliberately do
      # not (asking for a Hetzner id means asking for Hetzner).
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
      # UNRANKED — CheaperInference only (wallet-backed reseller, ci_live_ keys):
      # OpenAI/Anthropic models the ladder does not cover, plus the pay-per-token
      # twin of GLM-5.3. Explicit selection, cost-ordered tiers (docs/ai-ranks.md
      # "Pay-as-you-go"), promoted to a general-officer rank only when one moves
      # into standing use. Every model of the four ranked providers is in a rank;
      # nothing here is.
      #
      # Cost-tracked: these are real money. LiteLLM looks up pricing in its cost
      # map by `litellm_provider / model_name`; where the cost map has the
      # upstream row (`openai/gpt-5.6-luna`) we let it. Where it does not (the
      # other CI rows), pricing is pinned to zero with a TODO until the actual
      # discounted rates are known.
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

      # GLM-5.3 on the pay-per-token catalog: the cash twin of the Coding Plan's
      # glm-5.3 (which is the lieutenant-colonel rank, and the explicit `glm-5.3`
      # name above). Named -payg so the plan id and the cash id stay
      # distinguishable at the call site.
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

      # Cross-rank fallbacks — local + free-cloud only. Sergeant is deliberately
      # NOT in this chain: its Strata tier is the same deployment that
      # warrant-officer and second-lieutenant use as their local fallback, so a
      # rank entry would add no new capacity (only its Studio Nemotron tier would
      # be new, and that costs a model load). Sergeant is
      # explicit-selection-only. Paid ranks are explicit for the same reason
      # (silent cost escalation): captain, captain-v, captain-commandant, major,
      # major-v, lieutenant-colonel, lieutenant-colonel-v, brigadier-general,
      # brigadier-general-v, and every explicit model id — no fallback in or out
      # of any of them.
      fallbacks:
        - lieutenant: [second-lieutenant, warrant-officer]
        - second-lieutenant: [warrant-officer]
        # Vision cascade: -v ranks are the only image slots, so a vision
        # request falls only to another -v rank. Only the free ranks cascade;
        # the paid -v ranks (captain-v, major-v, lieutenant-colonel-v,
        # brigadier-general-v) are explicit. LiteLLM does NOT filter
        # deployments by vision capability pre-call (no such check exists in
        # 1.86.0 — verified in the source), so vision safety rests on every
        # deployment behind a -v name actually seeing images, plus the
        # client-side modality gate (opencode/pi only send images to
        # attachment-capable names).
        - lieutenant-v: [warrant-officer-v]

      # lieutenant -> second-lieutenant -> warrant-officer is two hops.
      max_fallbacks: 2

    litellm_settings:
      # Local GGUF backends reject parameters they don't know; drop them
      # instead of failing the request.
      drop_params: true
      # Proxy-wide default for deployments without their own timeout.
      request_timeout: 600

    general_settings:
      # Single master key for all clients; PostgreSQL backs the admin UI,
      # virtual keys, budgets and spend logs (see the design doc).
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
        # user@1000.service starts the user manager (logind linger=true);
        # strata.service runs inside it (autoStart=true). After= ensures the
        # proxy does not hit a refused port at boot; Wants= makes it a soft
        # dependency so the proxy still boots if the user manager is absent.
        after = [
          "network-online.target"
          "tailscale.service"
          "litellm-proxy-env.service"
          "litellm-proxy-ui.service"
          "postgresql.service"
          "user@1000.service"
        ];
        requires = [
          "litellm-proxy-env.service"
          "litellm-proxy-ui.service"
          "postgresql.service"
        ];
        wants = [
          "network-online.target"
          "tailscale.service"
          "user@1000.service"
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
