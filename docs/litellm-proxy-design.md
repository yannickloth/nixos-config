# LiteLLM Proxy Design

## Architecture

```
opencode / pi
    ↓  http://127.0.0.1:4000/v1  (LiteLLM proxy, single OpenAI-compatible endpoint)
    ↓  API key: sk-litellm-proxy  (one key for all clients)
LiteLLM Proxy (laptop-p16:4000)
    ├──→ Strata       (laptop-p16:8080)        — key: strata
    ├──→ Unsloth      (server-nike:8888)        — key: unsloth.key
    ├──→ Hetzner      (inference.hetzner.com)   — key: hetzner.key
    ├──→ DeepSeek     (api.deepseek.com)        — key: deepseek.key
    ├──→ Z.AI         (api.z.ai)                — key: zai.key
    ├──→ Kimi         (api.kimi.com)            — key: kimi.key
    └──→ CheaperInf   (api.cheaperinference.com) — key: cheaperinference.key
```

**Proxy location: laptop-p16** — closest to Strata (localhost), Unsloth via Tailscale, Hetzner from Europe.

## `config.yaml` — model_list

```yaml
model_list:
  # ===================================================================
  # ENLISTED — Fast executors (OR-1 to OR-4)
  # ===================================================================

  # OR-4 Sergeant — fast, faithful executor (Unsloth Studio, server-nike)
  - model_name: "sergeant"
    litellm_params:
      model: openai/nvidia/NVIDIA-Nemotron-3.5-Bolt-E4B-4GB
      api_base: http://server-nike.bee-blues.ts.net:8888
      api_key: unsloth.key
      temperature: 0.1      # deterministic execution
      timeout: 30           # fast model, short timeout

  # ===================================================================
  # WARRANT OFFICERS — Workhorse (OR-5 to OR-9)
  # ===================================================================
  # One rank, two deployments of the same model: local primary,
  # free-cloud redundant. LiteLLM load-balances across same-named
  # deployments (local preferred via weight) and fails over on error.

  # OR-8 Warrant Officer — deployment 1: local (primary)
  - model_name: "warrant-officer"
    litellm_params:
      model: openai/unsloth/Qwen3.6-35B-A3B-MTP-GGUF
      api_base: http://server-nike.bee-blues.ts.net:8888
      api_key: unsloth.key
    model_info:
      weight: 99

  # OR-8 Warrant Officer — deployment 2: free cloud (redundant)
  - model_name: "warrant-officer"
    litellm_params:
      model: openai/Qwen/Qwen3.6-35B-A3B-FP8
      api_base: https://inference.hetzner.com/v1
      api_key: hetzner.key
      timeout: 120          # Hetzner experimental, allow extra time
    model_info:
      weight: 1

  # ===================================================================
  # JUNIOR OFFICERS — Deep reasoning (OF-1a to OF-2)
  # ===================================================================

  # OF-1a Second Lieutenant — Swift 1.5's 27B base model, free cloud
  - model_name: "second-lieutenant"
    litellm_params:
      model: openai/Qwen3.8-27B
      api_base: https://inference.hetzner.com/v1
      api_key: hetzner.key
      timeout: 120

  # OF-1b Lieutenant — default model (Strata, laptop-p16)
  - model_name: "lieutenant"
    litellm_params:
      model: openai/swift-1.5-iq3_xxs
      api_base: http://laptop-p16.bee-blues.ts.net:8080/v1
      api_key: strata
      timeout: 300          # long context, allow time
  # Note: a small-window copy of the same model also runs on Unsloth
  # Studio (`ukisai/Swift-1.5-Qwen3.8-27B-GSQ-RCO-GGUF`, ~10K ctx).
  # Not a deployment here: 10K is too small for agentic sessions.

  # ===================================================================
  # SENIOR OFFICERS — Frontier coding subscriptions (OF-3 to OF-5)
  # ===================================================================
  # One rank, multiple deployments (Z.ai + Kimi) under the same name.
  # Enable cost/latency-based routing (litellm_settings.routing_strategy)
  # to prefer the cheaper-quota deployment within the rank.

  # OF-5 Lieutenant Colonel — GLM-5.3 (dense flagship, token-efficient)
  - model_name: "lieutenant-colonel"
    litellm_params:
      model: openai/glm-5.3
      api_base: https://api.z.ai/api/coding/paas/v4
      api_key: zai.key

  # OF-5 Lieutenant Colonel — Kimi K3 (2.8T params, flagship)
  - model_name: "lieutenant-colonel"
    litellm_params:
      model: openai/k3
      api_base: https://api.kimi.com/coding/v1
      api_key: kimi.key

  # OF-5 Lieutenant Colonel — Kimi K3, 256K window (cheaper quota)
  - model_name: "lieutenant-colonel"
    litellm_params:
      model: openai/k3-256k
      api_base: https://api.kimi.com/coding/v1
      api_key: kimi.key

  # OF-5 Lieutenant Colonel — Kimi K2.8 Preview (approaches K3)
  - model_name: "lieutenant-colonel"
    litellm_params:
      model: openai/kimi-for-coding
      api_base: https://api.kimi.com/coding/v1
      api_key: kimi.key

  # OF-5 Lieutenant Colonel (vision) — the multimodal model of the rank
  - model_name: "lieutenant-colonel-v"
    litellm_params:
      model: openai/glm-5.3-flash
      api_base: https://api.z.ai/api/coding/paas/v4
      api_key: zai.key

  # ===================================================================
  # PAY-AS-YOU-GO ESCALATION (unranked — named by model id)
  # ===================================================================
  # Unranked models have no rank abstraction, so they keep their model
  # ids as proxy names. No high-speed models in our stack (see
  # docs/ai-ranks.md).

  - model_name: "deepseek-flash"
    litellm_params:
      model: openai/deepseek-flash
      api_base: https://api.deepseek.com/v1
      api_key: deepseek.key

  - model_name: "deepseek-v4-pro"
    litellm_params:
      model: openai/deepseek-v4-pro
      api_base: https://api.deepseek.com/v1
      api_key: deepseek.key

  - model_name: "gpt-5.6-luna"
    litellm_params:
      model: openai/gpt-5.6-luna
      api_base: https://api.cheaperinference.com/v1
      api_key: cheaperinference.key

  - model_name: "claude-sonnet-5.5"
    litellm_params:
      # If CheaperInference only exposes the OpenAI-compatible route,
      # switch to the openai/ prefix with the same /v1 base.
      model: anthropic/claude-sonnet-5.5
      api_base: https://api.cheaperinference.com/v1
      api_key: cheaperinference.key

  - model_name: "claude-opus-5.5"
    litellm_params:
      model: anthropic/claude-opus-5.5
      api_base: https://api.cheaperinference.com/v1
      api_key: cheaperinference.key

  # ===================================================================
  # FUTURE — General Officer slots (OF-6 to OF-9)
  # Empty by design. A top-tier model assigned to a rank takes the
  # rank name (e.g. "brigadier-general") — never its model name.
  # ===================================================================
```

## `config.yaml` — aliases & fallbacks

```yaml
# No model_aliases: rank names are the only interface.

general_fallbacks:
  # Capability-ordered cascade. Fallbacks cross ranks only;
  # intra-rank deployment failover is LiteLLM's job (same model_name).
  lieutenant: [second-lieutenant, warrant-officer, sergeant]
  second-lieutenant: [warrant-officer, sergeant]
  warrant-officer: [sergeant]
  # sergeant: last local option — escalation to paid models is explicit

litellm_settings:
  drop_params: true
  retry_attempts: 2
  max_retries: 3
  request_timeout: 600
```

## opencode.json after LiteLLM

Ranked models use display names that describe the role, never the model — the rank is the abstraction and the deployment behind it may rotate. Unranked models have no abstraction: their name *is* the model id.

```json
{
  "$schema": "https://opencode.ai/config.json",
  "providers": {
    "proxy": {
      "package": "aisdk:@ai-sdk/openai-compatible",
      "settings": {
        "baseURL": "http://127.0.0.1:4000/v1",
        "apiKey": "{file:~/.config/opencode/keys/litellm-proxy.key}"
      },
      "models": {
        "sergeant": {
          "name": "Sergeant — fast executor",
          "limit": { "context": 65536, "output": 65536 }
        },
        "warrant-officer": {
          "name": "Warrant Officer — workhorse (local + free cloud)",
          "limit": { "context": 131072, "output": 32768 }
        },
        "second-lieutenant": {
          "name": "Second Lieutenant — free cloud reasoning",
          "limit": { "context": 262144, "output": 32768 }
        },
        "lieutenant": {
          "name": "Lieutenant — deep reasoning (default)",
          "limit": { "context": 393216, "output": 65536 }
        },
        "lieutenant-colonel": {
          "name": "Lieutenant Colonel — frontier coding (paid)",
          "limit": { "context": 262144, "output": 32768 }
        },
        "lieutenant-colonel-v": {
          "name": "Lieutenant Colonel (vision) — frontier multimodal (paid)",
          "limit": { "context": 1048576, "output": 131072 }
        },
        "deepseek-flash": {
          "name": "deepseek-flash (paid escalation)",
          "limit": { "context": 1048576, "output": 384000 }
        },
        "deepseek-v4-pro": {
          "name": "deepseek-v4-pro (paid escalation)",
          "limit": { "context": 1048576, "output": 384000 }
        },
        "gpt-5.6-luna": {
          "name": "gpt-5.6-luna (paid escalation)",
          "limit": { "context": 1000000, "output": 128000 }
        },
        "claude-sonnet-5.5": {
          "name": "claude-sonnet-5.5 (paid escalation)",
          "limit": { "context": 200000, "output": 64000 }
        },
        "claude-opus-5.5": {
          "name": "claude-opus-5.5 (paid escalation)",
          "limit": { "context": 200000, "output": 64000 }
        }
      }
    }
  },
  "mcp": {
    "servers": {
      "systemone": {
        "type": "remote",
        "url": "http://server-nike.bee-blues.ts.net:8888/mcp/decisions/",
        "oauth": false,
        "headers": {
          "Authorization": "Bearer {file:~/.config/opencode/keys/unsloth.key}"
        }
      },
      "designcraft": {
        "type": "local",
        "command": ["designcraft-cli", "mcp"]
      }
    }
  },
  "model": "proxy/lieutenant"
}
```

## Key management

Only one key file is needed for opencode/pi: `~/.config/opencode/keys/litellm-proxy.key`.

The LiteLLM proxy reads all backend keys directly from config or from its own key store. Backend keys are managed within the NixOS module, not exposed to opencode.

```nix
# Activation: generate the proxy API key
home.activation.setupLiteLLMKey = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
  proxykeyfile="${config.home.homeDirectory}/.config/opencode/keys/litellm-proxy.key"
  if [ ! -f "$proxykeyfile" ] || [ ! -s "$proxykeyfile" ]; then
    openssl rand -hex 32 > "$proxykeyfile"
    chmod 600 "$proxykeyfile"
  fi
'';
```

The proxy itself uses LiteLLM's built-in `api_key` or a `.env` file.

## Deployment

Using Docker:

```bash
docker run -d \
  --name litellm-proxy \
  --restart unless-stopped \
  -p 4000:4000 \
  -v ~/litellm/config.yaml:/app/config.yaml \
  --env-file ~/.litellm/proxy-env \
  ghcr.io/anthropic/litellm:main
```

Environment file (`~/.litellm/proxy-env`):
```env
PROXY_API_KEY=sk-litellm-proxy-<random>
```

## Telemetry & cost tracking (optional)

LiteLLM logs to SQLite by default (creates `litellm.db` in the working directory). Stores per-request metrics: model, tokens, latency, cost.

```yaml
litellm_settings:
  success_callback: ["llm_router"]
  failure_callback: ["llm_router"]
```

For docker: add `-v litellm-db:/app/db` to persist the SQLite database.

## NixOS systemd service

```nix
{ config, lib, pkgs, ... }:
let
  cfg = config.services.litellm-proxy;
in {
  options.services.litellm-proxy = {
    enable = lib.mkEnableOption "LiteLLM proxy";
    port = lib.mkOption { type = lib.types.port; default = 4000; };
    configYaml = lib.mkOption { type = lib.types.lines; };
    extraEnv = lib.mkOption { type = lib.types.attrsOf lib.types.str; default = {}; };
  };

  config = lib.mkIf cfg.enable {
    systemd.services.litellm-proxy = {
      description = "LiteLLM Proxy";
      after = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        ExecStart = "${pkgs.litellm}/bin/litellm --config /etc/litellm/config.yaml";
        Environment = builtins.concatStringsSep " " (
          lib.mapAttrsToList (k: v: "${k}=${v}") cfg.extraEnv
        );
        Restart = "unless-stopped";
        RuntimeDirectory = "litellm";
      };
    };

    environment.etc."litellm/config.yaml".text = cfg.configYaml;
  };
}
```
