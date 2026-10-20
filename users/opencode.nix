# Global opencode configuration for nicky: providers (deepseek, z.ai/GLM, Kimi,
# Hetzner, and on laptop-p16 the local Unsloth Studio server) and their models
# with researched context/output limits.
#
# API keys are NOT stored here or in the nix store. They are read at runtime via
# opencode's `{file:...}` substitution from per-key files that the
# setupOpenCodeKeys activation script materializes out of
# /etc/secrets/open-webui.env (itself decrypted by agenix, see
# services/secrets.nix). The activation runs as the user, who can read that file
# through the `secrets` group.
#
# Provider/model research (2026-08; Kimi corrected 2026-09):
#   deepseek  https://api.deepseek.com          V4 flash/pro: 1M ctx, 384K out
#   z.ai/GLM  https://api.z.ai/api/paas/v4/     glm-5.3 / glm-5.3-flash: 1M ctx, 128K out
#   Kimi      https://api.kimi.com/coding/v1    Kimi Code plan (subscription) IDs: k3 (1M ctx on
#                                               Allegretto+, else 256K), k3-256k, kimi-for-coding
#                                               (K2.8 Preview, 1M ctx), kimi-for-coding-highspeed
#                                               (256K, Allegretto+). The pay-per-token platform API
#                                               (api.moonshot.ai) uses different IDs (kimi-k3,
#                                               kimi-k2.7-code, kimi-k2.7-code-highspeed, kimi-k2.6).
#   Hetzner   https://inference.hetzner.com/api/v1   Qwen3.6-35B-A3B / Qwen3.8-27B: 256K ctx
#   cheaper   https://api.cheaperinference.com/v1   wallet-backed
#             OpenAI/Anthropic-compatible gateway (ci_live_... keys); model ids
#             vary, list them from GET /v1/models (no auto-discovery)
#   unsloth   http://127.0.0.1:8888/v1   local Unsloth Studio (laptop-p16 only);
#                                        Studio enforces its own per-model context budget
#   strata    http://127.0.0.1:8080/v1   local Strata server (laptop-p16 only); any
#                                        key/model name, context = packages/strata's
#                                        `strata.context` (default 524288)
{ config, lib, pkgs, ... }:

with lib;

let
  keyfile = name: "{file:~/.config/opencode/keys/${name}.key}";
  # Unsloth Studio is only installed on laptop-p16 (see nicky-hm.nix isP16),
  # so gate the local provider on the same build-time condition.
  isP16 = config.commonHm.hostName == "laptop-p16";
in
{
  options.opencode = {
    enable = mkEnableOption "opencode provider/model config (keys read from the env file below)";
    envFile = mkOption {
      type = types.str;
      default = "/etc/secrets/open-webui.env";
      description = ''
        Path to the OPENAI_API_KEYS env file the per-provider key files are
        materialized from. Defaults to the system agenix path (NixOS). Standalone
        home-manager hosts with no system agenix (CachyOS) point this at an
        `age.secrets` path decrypted with the user key; see
        users/nicky/nicky-hm.nix.
      '';
    };
  };

  config = mkIf config.opencode.enable {
    # The TypeSafe `jev` MCP entry below runs `npx -y @jkudish/jev-mcp`, so the
    # Node toolchain must be on PATH for every user with this module enabled
    # (previously only nicky had it via her own home.packages).
    home.packages = [ pkgs.nodejs ];

    xdg.configFile."opencode/opencode.json" = {
      text =
        let
          baseConfig = {
            "$schema" = "https://opencode.ai/config.json";
            provider = {
              # deepseek is a built-in opencode provider whose key already lives in
              # opencode auth; only refine the researched context/output limits.
              deepseek.models = {
                deepseek-v4-pro = {
                  name = "DeepSeek V4 Pro";
                  reasoning = true;
                  limit = {
                    context = 1000000;
                    output = 384000;
                  };
                };
                deepseek-flash = {
                  name = "DeepSeek Flash";
                  reasoning = true;
                  limit = {
                    context = 1000000;
                    output = 384000;
                  };
                };
              };
              zai = {
                npm = "@ai-sdk/openai-compatible";
                options = {
                  baseURL = "https://api.z.ai/api/paas/v4/";
                  apiKey = keyfile "zai";
                };
                models = {
                  "glm-5.3" = {
                    name = "GLM-5.3";
                    reasoning = true;
                    limit = {
                      context = 1000000;
                      output = 128000;
                    };
                  };
                  "glm-5.3-flash" = {
                    name = "GLM-5.3-Flash";
                    reasoning = true;
                    attachment = true;
                    limit = {
                      context = 1000000;
                      output = 128000;
                    };
                  };
                };
              };
              kimi = {
                npm = "@ai-sdk/openai-compatible";
                options = {
                  baseURL = "https://api.kimi.com/coding/v1";
                  apiKey = keyfile "kimi";
                };
                models = {
                  k3 = {
                    name = "Kimi K3";
                    reasoning = true;
                    attachment = true;
                    limit = {
                      context = 1048576;
                      output = 131072;
                    };
                  };
                  "k3-256k" = {
                    name = "Kimi K3 256K";
                    reasoning = true;
                    attachment = true;
                    limit = {
                      context = 262144;
                      output = 131072;
                    };
                  };
                  "kimi-for-coding" = {
                    name = "Kimi K2.8 Preview";
                    reasoning = true;
                    attachment = true;
                    limit = {
                      context = 1048576;
                      output = 131072;
                    };
                  };
                  "kimi-for-coding-highspeed" = {
                    name = "Kimi K2.7 Code HighSpeed";
                    reasoning = true;
                    attachment = true;
                    limit = {
                      context = 262144;
                      output = 65536;
                    };
                  };
                };
              };
              hetzner = {
                npm = "@ai-sdk/openai-compatible";
                options = {
                  baseURL = "https://inference.hetzner.com/api/v1";
                  apiKey = keyfile "hetzner";
                };
                models = {
                  "Qwen/Qwen3.6-35B-A3B-FP8" = {
                    name = "Qwen3.6-35B-A3B (Hetzner)";
                    limit = {
                      context = 262144;
                      output = 32768;
                    };
                  };
                  "Qwen3.8-27B" = {
                    name = "Qwen3.8-27B (Hetzner)";
                    limit = {
                      context = 262144;
                      output = 32768;
                    };
                  };
                };
              };
              # Cheaper Inference: wallet-backed OpenAI/Anthropic-compatible
              # gateway (https://cheaperinference.com). Keys look like
              # `ci_live_...`. opencode does NOT auto-discover models for custom
              # providers, so every model you want MUST be listed here with the
              # exact id from `GET https://api.cheaperinference.com/v1/models`.
              cheaperinference = {
                npm = "@ai-sdk/openai-compatible";
                name = "Cheaper Inference";
                options = {
                  baseURL = "https://api.cheaperinference.com/v1";
                  apiKey = keyfile "cheaperinference";
                };
                models = {
                  # Core combo, mapped to the tier-router roles. Effective
                  # prices are cheaperinference's discounted rates (2026-10).
                  # DeepSeek stays cheaper direct off-peak, so v4.1-flash here
                  # is for the 50% peak/cheap-tier discount + vision + speed.
                  "deepseek-v4.1-flash" = {
                    name = "DeepSeek V4.1 Flash (CI)";
                    reasoning = true;
                    attachment = true;
                    limit = {
                      context = 1048576;
                      output = 393216;
                    };
                  };
                  # Cheap GPT second-opinion: flash price, near-sonnet quality.
                  "gpt-5.6-luna" = {
                    name = "GPT-5.6 Luna (CI)";
                    reasoning = true;
                    attachment = true;
                    limit = {
                      context = 1050000;
                      output = 128000;
                    };
                  };
                  # Sonnet-tier workhorse reasoning/analysis (1M ctx, vision).
                  # 5.5 same price as 5.0 but faster (159 vs 91 tok/s) and more
                  # reliable (99.6% vs 95.9%).
                  "claude-sonnet-5.5" = {
                    name = "Claude Sonnet 5.5 (CI)";
                    reasoning = true;
                    attachment = true;
                    limit = {
                      context = 1000000;
                      output = 128000;
                    };
                  };
                  # Opus-tier deep formal reasoning (1M ctx, vision). 5.5 is
                  # cheaper and faster than 5 ($2.60/$13 vs $3.25/$16.25,
                  # 123 vs 78 tok/s).
                  "claude-opus-5.5" = {
                    name = "Claude Opus 5.5 (CI)";
                    reasoning = true;
                    attachment = true;
                    limit = {
                      context = 1000000;
                      output = 128000;
                    };
                  };
                  # Cheap 1M-in/1M-out reasoning cost-guard between flash and sonnet.
                  "glm-5.3" = {
                    name = "GLM-5.3 (CI)";
                    reasoning = true;
                    attachment = false;
                    limit = {
                      context = 1000000;
                      output = 1000000;
                    };
                  };
                };
              };
            } // optionalAttrs isP16 {
              # Local Unsloth Studio server: OpenAI-compatible API on localhost
              # (:8888). The model list below is the server's *local library*
              # (`curl -H "Authorization: Bearer $KEY"
              # http://127.0.0.1:8888/v1/models`, captured 2026-10-20), minus the
              # two local models that cannot answer a chat completion:
              #   unsloth/orpheus-3b-0.1-ft    TTS
              #   unsloth/Qwen-Image-2.1-GGUF  text-to-image
              #
              # `limit.context` is NOT the model's native window. Studio serves
              # 8192 by default and only a per-model override
              # (`custom_context_length` in Settings -> API, stored in
              # studio.db's app_settings.openai_api_auto_switch_overrides) raises
              # it; the live value is `context_length` in
              # `/api/inference/status` (loaded) or `/v1/models/<id>` (GGUF,
              # loaded). Keep this number <= that one: opencode compacts at
              # `limit.context`, so an inflated value ships prompts Studio
              # truncates. Auto-switch is on (openai_api_auto_switch_model), so
              # naming a downloaded model loads it; on laptop-p16 the
              # llama-server handoff wrapper unloads Strata first
              # (packages/unsloth-studio/home.nix).
              unsloth-studio = {
                npm = "@ai-sdk/openai-compatible";
                options = {
                  baseURL = "http://127.0.0.1:8888/v1";
                  # Studio requires an API key even for the local server. The key
                  # is read from ~/.config/opencode/keys/unsloth.key (materialized
                  # by setupOpenCodeKeys from /etc/secrets/open-webui.env).
                  apiKey = keyfile "unsloth";
                };
                models = {
                  # --- translation ------------------------------------------
                  # Served at 32768 tokens (native 262144 / 131072): Studio's
                  # 8192 default was raised with a custom_context_length
                  # override on 2026-10-20 so a multi-page document fits in one
                  # request. Raise the Studio override and this number together
                  # - never this one alone.
                  "unsloth/Hy-MT2-1.8B-GGUF" = {
                    name = "Hy-MT2 1.8B translation (local)";
                    limit = {
                      context = 32768;
                      output = 8192;
                    };
                  };
                  "mradermacher/translategemma-4b-it-GGUF" = {
                    name = "TranslateGemma 4B IT translation (local)";
                    attachment = true; # ships an mmproj: image -> translated text
                    limit = {
                      context = 32768;
                      output = 8192;
                    };
                  };

                  # --- chat -------------------------------------------------
                  # The one model here already pinned to 131072 in Studio
                  # (override on the UD-IQ3_XXS quant).
                  "unsloth/LFM2.5-24B-A2B-GGUF" = {
                    name = "LFM2.5 24B-A2B (local)";
                    limit = {
                      context = 131072;
                      output = 32768;
                    };
                  };
                  "unsloth/Llama-3.2-3B-Instruct-GGUF" = {
                    name = "Llama 3.2 3B Instruct (local)";
                    limit = {
                      context = 103424;
                      output = 32768;
                    };
                  };
                  "ornith-ai/Ornith-1.5-9B-GGUF" = {
                    name = "Ornith-1.5-9B (local)";
                    reasoning = true;
                    attachment = true; # mmproj (vision)
                    limit = {
                      context = 103424;
                      output = 32768;
                    };
                  };
                  "empero-ai/Qwythos-9B-Claude-Mythos-5-1M-GGUF" = {
                    name = "Qwythos-9B Claude-Mythos 1M (local)";
                    attachment = true; # mmproj (vision)
                    limit = {
                      context = 103424;
                      output = 32768;
                    };
                  };

                  # --- decisions --------------------------------------------
                  # System One family. Kev is the only download that is a
                  # decoder, so it is the only one that also answers
                  # /v1/chat/completions. Its native context is 262144; the
                  # 16384 here matches the Studio override, which is the
                  # useful ceiling on a 12 GB card.
                  #
                  # Do NOT add the mys/laya-* GGUFs here. Both carry
                  # general.architecture = "ggmlc", which llama.cpp rejects
                  # ("unknown model architecture"). They are private-format
                  # exports, not llama.cpp GGUFs, and a request for them
                  # wedges Studio's model switch. Laya runs through the
                  # Decision API instead, with catalog ids
                  # "laya-multilingual" / "laya-typed-decisions"; the
                  # /v1/systemone route answers "Unknown model" for repo ids.
                  "ggml-org/Kev-4B-GGUF" = {
                    name = "Kev 4B decisions (local)";
                    limit = {
                      context = 16384;
                      output = 4096;
                    };
                  };

                  # --- vision / OCR ----------------------------------------
                  # Single image in, short text out; the 131072 Studio setting
                  # from 2026-09-17 has to be re-entered (its override row is
                  # gone), or this number overstates what Studio serves.
                  "unsloth/GLM-OCR" = {
                    name = "GLM-OCR (local)";
                    attachment = true;
                    limit = {
                      context = 131072;
                      output = 32768;
                    };
                  };
                };
              };
              # Local Strata server (packages/strata, laptop-p16 only):
              # Qwen3.8-Flash-Next 125B MoE, OpenAI-compatible API on localhost.
              # The server accepts ANY API key and model name (chat.py sends
              # "strata"), so no key file is needed. Context is advisory (opencode
              # uses it for compaction thresholds) and must track the single
              # server context: packages/strata defaults to 524288 (yarn factor 2,
              # 8-bit KV streamed from pinned RAM; see strata.context). Vision is
              # OFF (vision = false): the strata-vision encoder drops throughput
              # from ~35 to ~22 tok/s, so attachments are disabled on both models.
              # reasoning=true: the model thinks before answering; tune via
              # reasoning effort.
              strata-local = {
                npm = "@ai-sdk/openai-compatible";
                options = {
                  baseURL = "http://127.0.0.1:8080/v1";
                  apiKey = "strata";
                };
                models = {
                  "qwen3.8-flash-next-125b" = {
                    name = "Strata Qwen3.8-Flash-Next 125B (local)";
                    reasoning = true;
                    attachment = false;
                    limit = {
                      context = 524288;
                      output = 65536;
                    };
                  };
                  "swift-1.5-iq3_xxs" = {
                    name = "Strata swift 1.5 IQ3_XXS (local)";
                    attachment = false;
                    limit = {
                      context = 524288;
                      output = 65536;
                    };
                  };
                };
              };
            };

            # Laya System 1 decision engine, served as a shared streamable-HTTP MCP
            # server by the packages/laya home-manager module. The MCP entry is
            # registered only when that feature is enabled for this user, but it is
            # DISABLED by default: laya is a local engine and when its checkpoint is
            # not loaded every call hung for the full 120s timeout. Routing/decisions
            # now go to deepseek-flash (see tier-router and the local_decide tool), so
            # flip `enabled` back to true only when laya is actually running.
            mcp = optionalAttrs (config.laya.enable or false)
              {
                laya = {
                  type = "remote";
                  url = "http://127.0.0.1:${toString (config.laya.mcpPort or 8765)}/mcp";
                  enabled = false;
                  timeout = 120000;
                };
              } // {
              # Jev judgment tools (@jkudish/jev-mcp), global so every project sees
              # them. They run against the local Unsloth Studio Decision API: a
              # TypeSafe-compatible POST /v1/systemone on Studio's port that
              # serves open System One models (Laya, ...). One Studio instance
              # per host, run as nicky with linger (see
              # packages/unsloth-studio/home.nix) — both users of this module
              # reach the same localhost endpoint. The MCP's `compatible`
              # provider takes the full POST URL in JEV_API_BASE_URL; under
              # Studio's Keyless-localhost setting the bearer is ignored, so a
              # literal keeps the provider resolver (which requires both vars)
              # happy without a key file.
              jev = {
                type = "local";
                command = [ "npx" "-y" "@jkudish/jev-mcp" ];
                environment = {
                  JEV_PROVIDER = "compatible";
                  JEV_API_BASE_URL = "http://127.0.0.1:8888/v1/systemone";
                  JEV_API_KEY = "keyless";
                };
                enabled = true;
              };
            } // optionalAttrs (pkgs ? rea) {
              # REA (packages/rea): reverse-engineering toolkit (native binaries,
              # JS/Electron, .NET, websites, ...) served over stdio MCP. Only
              # registered where the AI-unstable overlay provides pkgs.rea
              # (nicky, aeiuno). Set enabled = false to hide its large tool
              # catalog from every session.
              rea = {
                type = "local";
                command = [ "${pkgs.rea}/bin/rea" "mcp" ];
                enabled = true;
              };
            } // optionalAttrs (config.browseros.enable or false) {
              # BrowserOS neo: agent-driven browser exposing a local MCP server
              # (claw-server) on :9200. Agents drive the real browser (with the
              # user's imported Chrome logins) over typed MCP tool calls.
              browseros-neo = {
                type = "remote";
                url = "http://127.0.0.1:9200/mcp";
                enabled = true;
              };
            };
          };
        in
        builtins.toJSON (baseConfig // optionalAttrs isP16 {
          # Default model on laptop-p16: the local Strata swift-1.5 IQ3_XXS quant.
          model = "strata-local/swift-1.5-iq3_xxs";
        });
    };

    # Materialize per-provider API key files from a decrypted Open WebUI env
    # file (OPENAI_API_KEYS JSON). Source resolution, first existing wins:
    #   1. config.opencode.envFile — an `age.secrets` path on standalone
    #      home-manager hosts (CachyOS), or the system path on NixOS.
    #   2. /etc/secrets/open-webui.env — the system agenix path (NixOS hosts).
    # Skipped silently when neither exists.
    home.activation.setupOpenCodeKeys = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      ${pkgs.python3}/bin/python3 - "${config.home.homeDirectory}" '${config.opencode.envFile}' <<'PYEOF'
      import json, os, sys

      home = sys.argv[1]
      # expandvars so an agenix $XDG_RUNTIME_DIR/... path is resolved from the
      # activation environment rather than by bash before Python sees it.
      candidates = [os.path.expandvars(p) for p in (sys.argv[2], "/etc/secrets/open-webui.env") if p]
      envfile = next((p for p in candidates if p and os.path.exists(p)), None)
      keydir = os.path.join(home, ".config", "opencode", "keys")
      mapping = {
          "https://api.deepseek.com": "deepseek.key",
          "https://api.kimi.com/coding/v1": "kimi.key",
          "https://inference.hetzner.com/api/v1": "hetzner.key",
          "https://api.z.ai/api/paas/v4/": "zai.key",
          "http://127.0.0.1:8888/v1": "unsloth.key",
          "https://api.cheaperinference.com/v1": "cheaperinference.key",
      }
      if envfile is None:
          print("opencode: no key source found (%s); skipping key setup" % ", ".join(candidates))
          sys.exit(0)
      try:
          with open(envfile) as fh:
              _, _, payload = fh.read().partition("=")
          keys = json.loads(payload.strip())
      except Exception as exc:
          print(f"opencode: failed to parse {envfile}: {exc}; skipping key setup")
          sys.exit(1)
      os.makedirs(keydir, mode=0o700, exist_ok=True)
      for url, name in mapping.items():
          key = keys.get(url)
          if not key:
              print(f"opencode: no key for {url}; skipping {name}")
              continue
          path = os.path.join(keydir, name)
          fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
          with os.fdopen(fd, "w") as out:
              out.write(key + "\n")
          print(f"opencode: wrote {path}")
      PYEOF
    '';
  };
}
