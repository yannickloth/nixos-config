# Global opencode configuration for nicky: one LLM provider — the LiteLLM
# rank gateway on server-nike (services/litellm-proxy.nix) — in front of every
# local + paid backend, plus the per-model context/output limits researched
# for each rank and unranked model.
#
# The proxy owns routing, intra-rank failover (deployment order), cross-rank
# fallbacks, retries, timeouts and cost tracking — see
# docs/litellm-proxy-design.md. Model names below are rank names for the
# standing ladder (docs/ai-ranks.md) and plain model ids for the unranked pool
# (no rank abstraction: the id IS the model). Every host (laptop-p16 included)
# reaches the proxy over Tailscale: http://server-nike.bee-blues.ts.net:4000/v1.
#
# API keys are NOT stored here or in the nix store. They are read at runtime via
# opencode's `{file:...}` substitution from per-key files that the
# setupOpenCodeKeys activation script materializes out of
# /etc/secrets/opencode-keys.env (itself decrypted by agenix, see
# services/secrets.nix). The activation runs as the user, who can read that file
# through the `secrets` group. opencode itself only needs litellm-proxy.key
# (the proxy's master key); the backend key files are kept for tools that talk
# to a provider directly (the systemone MCP reads unsloth.key).
#
# Backends behind the proxy (the proxy config is the source of truth):
#   strata      http://laptop-p16.bee-blues.ts.net:8080/v1   (Strata on
#                  laptop-p16; any key; vision off; the long-context path)
#   unsloth     http://server-nike.bee-blues.ts.net:8888/v1  (Unsloth Studio on
#                  server-nike; Studio enforces its own per-model context budget)
#   hetzner     https://inference.hetzner.com/v1             (free cloud; the
#                  `/api` prefix 404s)
#   deepseek    https://api.deepseek.com                     (V4 flash/pro: 1M ctx,
#                  384K out)
#   z.ai/GLM    https://api.z.ai/api/coding/paas/v4          (GLM Coding Plan
#                  subscription; NOT the pay-per-token endpoint
#                  https://api.z.ai/api/paas/v4/ — a coding-plan key is rejected
#                  there and never draws the subscription quota)
#   Kimi        https://api.kimi.com/coding/v1               (Kimi Code plan;
#                  the pay-per-token platform API (api.moonshot.ai) uses
#                  different IDs)
#   cheaper     https://api.cheaperinference.com/v1          (wallet-backed
#                  OpenAI/Anthropic-compatible gateway, ci_live_... keys)
{ config, lib, pkgs, ... }:

with lib;

let
  keyfile = name: "{file:~/.config/opencode/keys/${name}.key}";
  hn = config.commonHm.hostName;
  # The local MCP servers (System One decisions via Unsloth Studio) only make
  # sense on the inference hosts; the LiteLLM proxy itself is reachable from
  # every host over Tailscale, so providers are no longer gated by this.
  hasLocalInference = hn == "laptop-p16" || hn == "server-nike";

  # Provider/model definitions shared by opencode and pi.
  #
  # Single provider: the LiteLLM rank gateway (services/litellm-proxy.nix, on
  # server-nike). The proxy fronts every backend; its config carries the
  # deployment order, fallbacks, timeouts and cost tracking (see
  # docs/litellm-proxy-design.md). This table only carries display names, the
  # researched context/output limits (opencode compacts at limit.context) and
  # the modality flags (consumed by pi).
  providers = {
    proxy = {
      package = "aisdk:@ai-sdk/openai-compatible";
      settings = {
        baseURL = "http://server-nike.bee-blues.ts.net:4000/v1";
        apiKey = keyfile "litellm-proxy";
      };
      models = {
        # --- rank ladder (standing stack: local + subscription) ----------
        "sergeant" = {
          name = "Sergeant — fast executor";
          limit = {
            context = 128256;
            output = 65536;
          };
        };
        "warrant-officer" = {
          name = "Warrant Officer — workhorse (local + free cloud)";
          # Group max (the Hetzner deployment serves 262K); prompts between
          # the local 131K and 262K are routed to the cloud deployment by the
          # proxy's pre-call context check.
          limit = {
            context = 262144;
            output = 32768;
          };
        };
        "second-lieutenant" = {
          name = "Second Lieutenant — free-cloud reasoning";
          limit = {
            context = 262144;
            output = 32768;
          };
        };
        "lieutenant" = {
          name = "Lieutenant — deep reasoning (default)";
          reasoning = true;
          limit = {
            context = 393216;
            output = 65536;
          };
        };
        "major" = {
          name = "Major — previous-generation coding (paid)";
          reasoning = true;
          attachment = true;
          limit = {
            context = 1048576;
            output = 131072;
          };
        };
        "lieutenant-colonel" = {
          name = "Lieutenant Colonel — frontier coding (paid)";
          reasoning = true;
          limit = {
            context = 1000000;
            output = 131072;
          };
        };
        "lieutenant-colonel-v" = {
          name = "Lieutenant Colonel (vision) — frontier multimodal (paid)";
          reasoning = true;
          attachment = true;
          limit = {
            context = 1048576;
            output = 131072;
          };
        };

        # --- unranked (pay-as-you-go pool; explicit selection) -----------
        "deepseek-flash" = {
          name = "deepseek-flash (paid escalation)";
          reasoning = true;
          attachment = true;
          limit = {
            context = 1000000;
            output = 384000;
          };
        };
        "deepseek-v4-pro" = {
          name = "deepseek-v4-pro (paid escalation)";
          reasoning = true;
          limit = {
            context = 1000000;
            output = 384000;
          };
        };
        "deepseek-v4.1-flash" = {
          name = "deepseek-v4.1-flash (paid escalation, CI)";
          reasoning = true;
          attachment = true;
          limit = {
            context = 1048576;
            output = 393216;
          };
        };
        "gpt-5.6-luna" = {
          name = "gpt-5.6-luna (paid escalation)";
          reasoning = true;
          attachment = true;
          limit = {
            context = 1050000;
            output = 128000;
          };
        };
        "claude-sonnet-5.5" = {
          name = "claude-sonnet-5.5 (paid escalation)";
          reasoning = true;
          attachment = true;
          limit = {
            context = 1000000;
            output = 128000;
          };
        };
        "claude-opus-5.5" = {
          name = "claude-opus-5.5 (paid escalation)";
          reasoning = true;
          attachment = true;
          limit = {
            context = 1000000;
            output = 128000;
          };
        };
        "glm-5.3" = {
          name = "glm-5.3 (paid, per-token)";
          reasoning = true;
          limit = {
            context = 1000000;
            output = 1000000;
          };
        };
      };
    };
  };

  # pi (pi-coding-agent) reads ~/.pi/agent/models.json. It speaks the same
  # OpenAI-compatible endpoints, but a different schema: api/baseUrl instead of
  # npm/options.baseURL, and contextWindow/maxTokens instead of
  # limit.{context,output}. Its config is generated from `providers` above so
  # the two agents cannot drift apart.
  #
  # There is only one provider now (the LiteLLM rank gateway), and pi does not
  # ship a native catalog for it, so every provider is emitted as a full
  # openai-completions definition. `piNativeIds` stays empty.
  piNativeIds = { };

  # opencode stores keys as {file:...} interpolations; pi resolves a leading
  # "!" as a command at request time. Reuse the very same key files (materialized
  # by setupOpenCodeKeys) instead of exporting a parallel set of variables.
  piKey = value:
    let inner = removePrefix "{file:" value;
    in
    if inner != value && hasSuffix "}" inner then
      "!cat ${removeSuffix "}" inner}"
    else
      value;

  piModel = id: model: {
    inherit id;
    name = model.name or id;
    reasoning = model.reasoning or false;
    input = if model.attachment or false then [ "text" "image" ] else [ "text" ];
    contextWindow = model.limit.context;
    maxTokens = model.limit.output;
  };

  # Emit every provider as a full openai-completions definition (pi has no
  # native catalog for the LiteLLM rank gateway).
  piProviders = listToAttrs (
    concatMap
      (name:
        let
          provider = providers.${name};
          options = provider.settings or { };
        in
        optional (options != { }) {
          inherit name;
          value = {
            api = "openai-completions";
            baseUrl = options.baseURL;
            apiKey = piKey options.apiKey;
            models = mapAttrsToList piModel provider.models;
          };
        })
      (attrNames providers)
  );
in
{
  options.opencode = {
    enable = mkEnableOption "opencode provider/model config (keys read from the env file below)";
    envFile = mkOption {
      type = types.str;
      default = "/etc/secrets/opencode-keys.env";
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
    # openspec (openspec.dev) is the spec-driven workflow CLI: `openspec init
    # --tools opencode` in a project writes .opencode/skills/openspec-* and
    # .opencode/commands/opsx-*.md, and `openspec update` refreshes them. It is
    # not an MCP server and not a provider, so it only needs to be on PATH.
    home.packages =
      [ pkgs.nodejs ]
      # ++ lib.optional (pkgs ? open-code-review) pkgs.open-code-review  # disabled
      ++ lib.optional (pkgs ? openspec) pkgs.openspec;

    xdg.configFile."opencode/opencode.json" = {
      # opencode (and anything else that opens the file) replaces the store
      # symlink with a regular file, so a stale opencode.json.backup from an
      # earlier `-b backup` run made every later switch stop at
      # checkFilesChanged. force overwrites the file instead of backing it up:
      # this repo is the only writer, and a manual edit is discarded on purpose.
      force = true;
      text =
        let
          # Strip V1-only model fields (reasoning, attachment) that opencode V2
          # ignores, while keeping them in the source `providers` for pi.
          stripV1 = provider:
            if provider ? package then
              provider // {
                models = lib.mapAttrs (id: model:
                  removeAttrs model [ "reasoning" "attachment" ]
                ) provider.models;
              }
            else
              provider;
          baseConfig = {
            "$schema" = "https://opencode.ai/config.json";
            providers = lib.mapAttrs (_name: stripV1) providers;
            # System One decision tools come from Unsloth Studio only. The old
            # packages/laya MCP server (a separate streamable-HTTP endpoint on
            # port 8765) is gone with the package: Studio's Decision API serves
            # the same shape locally, so there is nothing else to register.
            # Z.AI's built-in pay-per-token catalog is irrelevant now: the only
            # Z.AI access is through the LiteLLM proxy's rank deployments.
            mcp = optionalAttrs hasLocalInference {
              servers = {
                # System One decision tools straight from local Unsloth Studio, so
                # decisional prompts stay on this machine. Studio serves this
                # itself: routes/systemone.py builds a FastMCP ("Unsloth
                # Decisions") mounted at /mcp/decisions with stateless_http and
                # json_response, exposing one tool, `decide(state, questions)`,
                # whose schema documents the noul / choice / score question types.
                # So there is no vendor client and no npx package to pin; the
                # endpoint runs Laya on CPU (see packages/unsloth-studio/home.nix).
                #
                # Auth is the owner's Studio key — the same file
                # setupOpenCodeKeys materializes as ~/.config/opencode/keys/unsloth.key.
                # /mcp/decisions is wrapped in RequireStudioAuth, which calls
                # security() directly and so bypasses keyless admission: a dummy
                # bearer gets 401 (verified), the real key gets 200. oauth = false
                # because this is a header credential, not an OAuth server.
                #
                # Tools surface as systemone_<tool> (here systemone_decide). If the
                # connection reports 401, the `{file:}` substitution is not being
                # applied inside headers on this OpenCode build; switch to
                # "Bearer {env:UNSLOTH_API_KEY}" and export that variable.
                systemone = {
                  type = "remote";
                  url = "http://server-nike.bee-blues.ts.net:8888/mcp/decisions/";
                  oauth = false;
                  disabled = false;
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
                #
                # DesignCraft (packages/craft-apps): page layout/publishing
                # (clean-room InDesign reimplementation). The CLI binary
                # designcraft-cli serves MCP over stdio — ask it to make
                # layouts, export, or run scripts.
                designcraft = {
                  type = "local";
                  command = [ "${(import ../packages/craft-apps { pkgs = pkgs; }).designcraft}/bin/designcraft-cli" "mcp" ];
                  disabled = false;
                };
              } // optionalAttrs (pkgs ? rea) {
                # REA (packages/rea): reverse-engineering toolkit (native binaries,
                # JS/Electron, .NET, websites, ...) served over stdio MCP. Only
                # registered where the AI-unstable overlay provides pkgs.rea
                # (nicky, aeiuno). Set disabled = false to hide its large tool
                # catalog from every session.
                rea = {
                  type = "local";
                  command = [ "${pkgs.rea}/bin/rea" "mcp" ];
                  disabled = false;
                };
              } // optionalAttrs (config.browseros.enable or false) {
                # BrowserOS neo: agent-driven browser exposing a local MCP server
                # (claw-server) on :9010. Agents drive the real browser (with the
                # user's imported Chrome logins) over typed MCP tool calls.
                browseros-neo = {
                  type = "remote";
                  url = "http://127.0.0.1:9010/mcp";
                  disabled = false;
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
                  disabled = false;
                };
              };
            };
          };
        in
        builtins.toJSON (baseConfig // {
          # Default model: the LiteLLM rank gateway's lieutenant rank
          # (Swift 1.5 via Strata on laptop-p16). Same on every host.
          model = "proxy/lieutenant";
        });
    };

    # pi (pi-coding-agent): same provider set as opencode, generated from the
    # `providers` table above (see piProviders). A store symlink is safe here
    # because pi only reads models.json — its cache (models-store.json) and
    # settings.json live next to it and stay writable.
    home.file.".pi/agent/models.json".text = builtins.toJSON {
      "$schema" = "https://pi.dev/schemas/models.schema.json";
      providers = piProviders;
    };

    # disabled — Open Code Review's official OpenCode integration: native
    # ocr_review / ocr_health tools plus /ocr-review and /ocr-health slash
    # commands (plugins/open-code-review/opencode in alibaba/open-code-review,
    # pinned to the same release as the ocr CLI in home.packages above). opencode
    # auto-loads *.ts from the plugins/ directory; the file's SDK imports must
    # resolve from ~/.config/opencode/node_modules, which opencode does not
    # provide itself — hence the node_modules symlink (OpenCode 2.x needs
    # both @opencode-ai/plugin and @opencode/plugin; see
    # packages/open-code-review/plugin-deps.nix).
    # xdg.configFile."opencode/plugins/open-code-review.ts".source =
    #   lib.mkIf (pkgs ? open-code-ocr-plugin) "${pkgs.open-code-ocr-plugin}/plugin/open-code-review.ts";
    # xdg.configFile."opencode/node_modules".source =
    #   lib.mkIf (pkgs ? open-code-ocr-plugin) "${pkgs.open-code-ocr-plugin}/node_modules";

    # Materialize per-provider API key files from the decrypted provider-key env
    # file (OPENAI_API_KEYS JSON). Source resolution, first existing wins:
    #   1. config.opencode.envFile — an `age.secrets` path on standalone
    #      home-manager hosts (CachyOS), or the system path on NixOS.
    #   2. /etc/secrets/opencode-keys.env — the system agenix path (NixOS hosts).
    # Skipped silently when neither exists.
    # Bun standalone can't resolve bundled @opencode/ai providers via dynamic
    # import — it falls back to filesystem resolution. The binary adds
    # ~/.node_modules to module resolution paths AND looks at ~/@opencode/ for
    # scoped packages. Install @opencode/ai in both locations.
    home.activation.setupOpenCodeAIDeps = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      for dir in "${config.home.homeDirectory}/.node_modules" "${config.home.homeDirectory}/@opencode"; do
        mkdir -p "$dir"
        ${pkgs.bun}/bin/bun --cwd "$dir" install @opencode/ai 2>&1 || true
      done
    '';

    home.activation.setupOpenCodeKeys = lib.hm.dag.entryAfter [ "writeBoundary" "setupOpenCodeAIDeps" ] ''
      ${pkgs.python3}/bin/python3 - "${config.home.homeDirectory}" '${config.opencode.envFile}' <<'PYEOF'
      import json, os, sys

      home = sys.argv[1]
      # expandvars so an agenix $XDG_RUNTIME_DIR/... path is resolved from the
      # activation environment rather than by bash before Python sees it.
      candidates = [os.path.expandvars(p) for p in (sys.argv[2], "/etc/secrets/opencode-keys.env") if p]
      envfile = next((p for p in candidates if p and os.path.exists(p)), None)
      keydir = os.path.join(home, ".config", "opencode", "keys")
      mapping = {
          "https://api.deepseek.com": "deepseek.key",
          "https://api.kimi.com/coding/v1": "kimi.key",
          "https://inference.hetzner.com/api/v1": "hetzner.key",
          # The GLM Coding Plan key is stored in the secret's OPENAI_API_KEYS
          # JSON under the *general* Z.AI URL (the secret still lists that base
          # URL), so both spellings map to the same key file. The provider above
          # talks to the coding-plan endpoint; this dict is only the secret
          # lookup key, never the URL opencode requests.
          "https://api.z.ai/api/paas/v4/": "zai.key",
          "https://api.z.ai/api/coding/paas/v4": "zai.key",
          "http://server-nike.bee-blues.ts.net:8888/v1": "unsloth.key",
          "https://api.cheaperinference.com/v1": "cheaperinference.key",
          # LiteLLM proxy master key (also used by services/litellm-proxy.nix).
          "http://server-nike.bee-blues.ts.net:4000/v1": "litellm-proxy.key",
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

    # pi rewrites ~/.pi/agent/settings.json from its TUI, so that file cannot be
    # a store symlink. Repair stale defaultModel values this repo shipped: the
    # old direct-provider ids are gone, and the new default is the LiteLLM
    # rank gateway's lieutenant rank. Any other value — including one chosen
    # later in the TUI — is left untouched.
    home.activation.piSettings = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      ${pkgs.python3}/bin/python3 - "${config.home.homeDirectory}" <<'PYEOF'
      import json, os, sys

      path = os.path.join(sys.argv[1], ".pi", "agent", "settings.json")
      try:
          with open(path, encoding="utf-8") as fh:
              settings = json.load(fh)
      except FileNotFoundError:
          sys.exit(0)
      except Exception as exc:
          print(f"pi: cannot parse {path}: {exc}; leaving it untouched", file=sys.stderr)
          sys.exit(0)
      stale = {
          "deepseek-v4-flash": "proxy/lieutenant",
          "unsloth-studio/unsloth/Qwen3.6-35B-A3B-MTP-GGUF": "proxy/lieutenant",
          "strata-local/swift-1.5-iq3_xxs": "proxy/lieutenant",
      }
      current = settings.get("defaultModel")
      if current not in stale:
          sys.exit(0)
      settings["defaultModel"] = stale[current]
      fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
      os.fchmod(fd, 0o600)
      with os.fdopen(fd, "w", encoding="utf-8") as fh:
          json.dump(settings, fh, indent=2)
          fh.write("\n")
      print(f"pi: repaired stale defaultModel in {path}")
      PYEOF
    '';
  };
}
