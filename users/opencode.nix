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
#   unsloth   http://127.0.0.1:8888/v1   local Unsloth Studio (laptop-p16 only, keyless);
#                                        Studio enforces its own per-model context budget
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
    enable = mkEnableOption "opencode provider/model config (keys read from /etc/secrets/open-webui.env)";
  };

  config = mkIf config.opencode.enable {
    xdg.configFile."opencode/opencode.json" = {
      text = builtins.toJSON {
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
        } // optionalAttrs isP16 {
          # Local Unsloth Studio server: OpenAI-compatible API on localhost.
          # Model list captured from `curl http://127.0.0.1:8888/v1/models`
          # (2026-09-16). The TTS (unsloth/orpheus-*) and text-to-image
          # (unsloth/Qwen-Image-*) entries are excluded: opencode only speaks
          # chat completions. Download/load new models in the Studio UI, then
          # add matching entries here; limits are advisory (opencode uses them
          # for compaction thresholds) and set to the ~100K budget Studio
          # actually serves per loaded model, well under the native windows.
          unsloth = {
            npm = "@ai-sdk/openai-compatible";
            options = {
              baseURL = "http://127.0.0.1:8888/v1";
              # Studio's keyless mode rejects any non-empty bearer token but
              # accepts an empty one, which the ai-sdk sends for apiKey "".
              apiKey = "";
            };
            models = {
              "empero-ai/Qwen3.8-9B-Distill-GGUF" = {
                name = "Qwen3.8-9B Distill (local)";
                reasoning = true;
                limit = {
                  context = 103424;
                  output = 32768;
                };
              };
              "ornith-ai/Ornith-1.5-9B-GGUF" = {
                name = "Ornith-1.5-9B (local)";
                limit = {
                  context = 103424;
                  output = 32768;
                };
              };
              "unsloth/qwen3.8-27B-GGUF" = {
                name = "Qwen3.8-27B (local)";
                reasoning = true;
                limit = {
                  context = 103424;
                  output = 32768;
                };
              };
              "empero-ai/Qwen3.8-27B-Ridge-GGUF" = {
                name = "Qwen3.8-27B Ridge (local)";
                reasoning = true;
                limit = {
                  context = 103424;
                  output = 32768;
                };
              };
              "empero-ai/Qwythos-9B-v2-GGUF" = {
                name = "Qwythos-9B v2 (local)";
                limit = {
                  context = 103424;
                  output = 32768;
                };
              };
              "empero-ai/Qwythos-9B-Claude-Mythos-5-1M-GGUF" = {
                name = "Qwythos-9B Claude-Mythos 1M (local)";
                limit = {
                  context = 103424;
                  output = 32768;
                };
              };
              "unsloth/gemma-4-12B-it-qat-GGUF" = {
                name = "Gemma-4-12B IT QAT (local)";
                limit = {
                  context = 103424;
                  output = 32768;
                };
              };
              # Vision OCR model. Studio serves it with a tiny default
              # context budget (4K); expanded to 131072 in the Studio UI
              # (2026-09-17), so the advisory limit matches that.
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
        };

        # Laya System 1 decision engine, served as a shared streamable-HTTP MCP
        # server by the packages/laya home-manager module. Enabled whenever that
        # feature is enabled for this user (nicky gates it on laptop-p16). The
        # `or` defaults keep this module usable without importing packages/laya.
        # The long timeout covers a cold checkpoint load on first connect.
        mcp = optionalAttrs (config.laya.enable or false) {
          laya = {
            type = "remote";
            url = "http://127.0.0.1:${toString (config.laya.mcpPort or 8765)}/mcp";
            enabled = true;
            timeout = 120000;
          };
        };
      };
    };

    # Materialize per-provider API key files from the decrypted Open WebUI env
    # file (OPENAI_API_KEYS JSON). Skipped silently when the file is absent.
    home.activation.setupOpenCodeKeys = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      ${pkgs.python3}/bin/python3 - "${config.home.homeDirectory}" <<'PYEOF'
      import json, os, sys

      home = sys.argv[1]
      envfile = "/etc/secrets/open-webui.env"
      keydir = os.path.join(home, ".config", "opencode", "keys")
      mapping = {
          "https://api.deepseek.com": "deepseek.key",
          "https://api.kimi.com/coding/v1": "kimi.key",
          "https://inference.hetzner.com/api/v1": "hetzner.key",
          "https://api.z.ai/api/paas/v4/": "zai.key",
      }
      if not os.path.exists(envfile):
          print(f"opencode: {envfile} missing; skipping key setup")
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
