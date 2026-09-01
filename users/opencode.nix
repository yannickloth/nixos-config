# Global opencode configuration for nicky: providers (deepseek, z.ai/GLM, Kimi,
# Hetzner) and their models with researched context/output limits.
#
# API keys are NOT stored here or in the nix store. They are read at runtime via
# opencode's `{file:...}` substitution from per-key files that the
# setupOpenCodeKeys activation script materializes out of
# /etc/secrets/open-webui.env (itself decrypted by agenix, see
# services/secrets.nix). The activation runs as the user, who can read that file
# through the `secrets` group.
#
# Provider/model research (2026-08):
#   deepseek  https://api.deepseek.com          V4 flash/pro: 1M ctx, 384K out
#   z.ai/GLM  https://api.z.ai/api/paas/v4/     glm-5.3 / glm-5.3-flash: 1M ctx, 128K out
#   Kimi      https://api.kimi.com/coding/v1    kimi-k3: 1M ctx; k2.7-code/k2.6: 256K ctx
#   Hetzner   https://inference.hetzner.com/api/v1   Qwen3.6-35B-A3B / Qwen3.8-27B: 256K ctx
{ config, lib, pkgs, ... }:

with lib;

let
  keyfile = name: "{file:~/.config/opencode/keys/${name}.key}";
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
            deepseek-v4-flash = {
              name = "DeepSeek V4 Flash";
              reasoning = true;
              limit = {
                context = 1000000;
                output = 384000;
              };
            };
            deepseek-v4-flash-vision-exp = {
              name = "DeepSeek V4 Flash Vision";
              reasoning = true;
              attachment = true;
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
              kimi-k3 = {
                name = "Kimi K3";
                reasoning = true;
                attachment = true;
                limit = {
                  context = 1048576;
                  output = 131072;
                };
              };
              "kimi-k2.7-code" = {
                name = "Kimi K2.7 Code";
                reasoning = true;
                limit = {
                  context = 262144;
                  output = 65536;
                };
              };
              "kimi-k2.7-code-highspeed" = {
                name = "Kimi K2.7 Code HighSpeed";
                reasoning = true;
                limit = {
                  context = 262144;
                  output = 65536;
                };
              };
              "kimi-k2.6" = {
                name = "Kimi K2.6";
                attachment = true;
                limit = {
                  context = 262144;
                  output = 32768;
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
