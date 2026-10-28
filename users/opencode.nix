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
    # Node toolchain (npx): the skills install flows documented in
    # packages/{orca,browseros,rea} are `npx skills add ...`, so npx stays on
    # PATH for every user with this module enabled. open-code-review
    # (ocr) is Alibaba's AI code-review CLI: it consumes the LLM providers
    # configured below (via `ocr config provider`, or delegation mode) — it is
    # not a provider itself (open-codereview.ai serves no LLM API; see
    # packages/open-code-review).
    home.packages = [ pkgs.nodejs ] ++ lib.optional (pkgs ? open-code-review) pkgs.open-code-review;

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

            # System One decision tools come from Unsloth Studio only. The old
            # packages/laya MCP server (a separate streamable-HTTP endpoint on
            # port 8765) is gone with the package: Studio's Decision API serves
            # the same shape locally, so there is nothing else to register.
            mcp = optionalAttrs isP16 {
              # System One decision tools straight from local Unsloth Studio, so
              # decisional prompts stay on this machine. Studio serves this
              # itself: routes/systemone.py builds a FastMCP ("Unsloth
              # Decisions") mounted at /mcp/decisions with stateless_http and
              # json_response, exposing one tool, `decide(state, questions)`,
              # whose schema documents the noul / choice / score question types.
              # So there is no vendor client and no npx package to pin; the
              # endpoint runs Laya on CPU (see packages/unsloth-studio/home.nix).
              #
              # Auth is the owner's Studio key — the same file the
              # unsloth-studio provider reads. /mcp/decisions is wrapped in
              # RequireStudioAuth, which calls security() directly and so
              # bypasses keyless admission: a dummy bearer gets 401 (verified),
              # the real key gets 200. oauth = false because this is a header
              # credential, not an OAuth server.
              #
              # Tools surface as systemone_<tool> (here systemone_decide). If the
              # connection reports 401, the `{file:}` substitution is not being
              # applied inside headers on this OpenCode build; switch to
              # "Bearer {env:UNSLOTH_API_KEY}" and export that variable.
              systemone = {
                type = "remote";
                url = "http://127.0.0.1:8888/mcp/decisions/";
                oauth = false;
                enabled = true;
                headers = {
                  Authorization = "Bearer ${keyfile "unsloth"}";
                };
              };

              # No Jev MCP here on purpose. The `@jkudish/jev-mcp` stdio server
              # shipped 12 prompt decompositions (screen, verify, noul, find,
              # rerank, classify, decide, compare, extract, audit, review, gate)
              # over the same local System One primitive `systemone_decide`
              # exposes raw — so it added a third-party `npx -y` package that
              # executes JS against this state, and nothing the local plugin
              # does not cover. Those workflows now live in the systemone plugin
              # (llm-harness-plugins/systemone) against the local decision API.
              # Do not re-add a hosted Jev client here: it would send local
              # judgment prompts to a third party.
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
              # (claw-server) on :9010. Agents drive the real browser (with the
              # user's imported Chrome logins) over typed MCP tool calls.
              browseros-neo = {
                type = "remote";
                url = "http://127.0.0.1:9010/mcp";
                enabled = true;
              };
            } // optionalAttrs (config.libreofficeMcp.enable or false) {
              # LibreOffice MCP (packages/libreoffice-mcp): the extension serves
              # streamable HTTP from inside the running soffice process, so its
              # tools act on the document the user has open, not on a copy.
              # Upstream exposes /, /health (liveness only) and /mcp (the MCP
              # endpoint) on the configured port; /health is not MCP.
              #
              # Local-only, by design: the server binds IPv4 loopback (the
              # artifact pins Host=127.0.0.1) and upstream's tunnel support is
              # left off. The URL spells out 127.0.0.1 rather than "localhost"
              # because this host resolves localhost to ::1 first, which the
              # server does not listen on — the numeric address makes client and
              # socket agree without relying on Happy Eyeballs fallback.
              #
              # The generated cert has to reach Node-based MCP clients: the
              # extension serves TLS with a self-signed cert (SAN localhost +
              # 127.0.0.1, generated into ~/.config/libreoffice/mcp-certs on
              # first start, which also keeps browser-origin requests out — the
              # server sends Access-Control-Allow-Origin: *).
              # packages/libreoffice-mcp/home.nix exports it as
              # NODE_EXTRA_CA_CERTS, which is how opencode's Node fetch trusts
              # it. Without that variable the connection fails with a
              # self-signed certificate error, so a failed connection here
              # usually means: env var missing (app started outside the HM
              # session), LibreOffice closed, or the extension not loaded.
              #
              # The port comes from the same option that is patched into the
              # extension (libreofficeMcp.port), never a hardcoded 8765, so two
              # users on one host do not attach to each other's documents.
              libreoffice = {
                type = "remote";
                url = "https://127.0.0.1:${toString config.libreofficeMcp.port}/mcp";
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

    # Open Code Review's official OpenCode integration: native ocr_review /
    # ocr_health tools plus /ocr-review and /ocr-health slash commands
    # (plugins/open-code-review/opencode in alibaba/open-code-review, pinned
    # to the same release as the ocr CLI in home.packages above). opencode
    # auto-loads *.ts from the plugins/ directory; the file's SDK imports must
    # resolve from ~/.config/opencode/node_modules, which opencode does not
    # provide itself — hence the node_modules symlink (OpenCode 2.x needs
    # both @opencode-ai/plugin and @opencode/plugin; see
    # packages/open-code-review/plugin-deps.nix).
    xdg.configFile."opencode/plugins/open-code-review.ts".source =
      lib.mkIf (pkgs ? open-code-ocr-plugin) "${pkgs.open-code-ocr-plugin}/plugin/open-code-review.ts";
    xdg.configFile."opencode/node_modules".source =
      lib.mkIf (pkgs ? open-code-ocr-plugin) "${pkgs.open-code-ocr-plugin}/node_modules";

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
          print(f"opencode: failed to parse {envfile}: {exc}; leaving existing keys untouched", file=sys.stderr)
          sys.exit(0)
      os.makedirs(keydir, mode=0o700, exist_ok=True)
      os.chmod(keydir, 0o700)
      for url, name in mapping.items():
          key = keys.get(url)
          if not key:
              print(f"opencode: no key for {url}; skipping {name}")
              continue
          path = os.path.join(keydir, name)
          fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
          # O_CREAT only applies the mode on creation; tighten existing files.
          os.fchmod(fd, 0o600)
          with os.fdopen(fd, "w") as out:
              # No trailing newline: these files are read back through the
              # file: interpolation used by provider apiKey values and MCP
              # headers, and an `Authorization: Bearer` header would otherwise
              # carry the newline in the token (a protocol error, or a silently
              # invalid credential).
              out.write(key)
          print(f"opencode: wrote {path}")
      # Repair files the secret no longer supplies, and any left by an older
      # version of this script. Without this, a key whose URL was dropped from
      # the secret stays on disk with its trailing newline, and that newline
      # rides inside an `Authorization: Bearer {file:...}` header as a silently
      # invalid credential. (Exactly what happened to unsloth.key.)
      for entry in sorted(os.listdir(keydir)):
          path = os.path.join(keydir, entry)
          if os.path.islink(path) or not os.path.isfile(path):
              continue
          try:
              with open(path, encoding="utf-8") as fh:
                  current = fh.read()
              stripped = current.rstrip()
              if stripped == current:
                  continue
              fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
              os.fchmod(fd, 0o600)
              with os.fdopen(fd, "w", encoding="utf-8") as out:
                  out.write(stripped)
              print(f"opencode: normalized {path}")
          except OSError as exc:
              print(f"opencode: could not normalize {path}: {exc}", file=sys.stderr)
      PYEOF
    '';
  };
}
