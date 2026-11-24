# Global opencode configuration for nicky: the LiteLLM rank gateway
# (services/litellm-proxy.nix) as the primary provider — in front of every
# local + paid backend — plus one DIRECT provider per backend, so the
# subscription and other models stay usable when the gateway itself is
# down (the proxy host offline, its litellm unit failed, or the Tailscale
# path gone). Both paths share one model card per model; see the shared
# *Models bindings and DIRECT PROVIDERS below.
#
# The proxy owns routing, intra-rank failover (deployment order), cross-rank
# fallbacks, retries, timeouts and cost tracking — see
# docs/litellm-proxy-design.md. Model names below are rank names for the ladder
# (docs/ai-ranks.md — every model of every ranked provider holds a rank slot)
# plus one explicit name per ranked model, spelled like its upstream id, for
# callers that want the model itself. The unranked pool is CheaperInference only
# (plus glm-5.3-payg, the cash twin of the Coding Plan's glm-5.3). The proxy
# runs on server-nike and on laptop-p16 (same config). A host uses the local
# instance when it runs one (laptop-p16 on NixOS → http://127.0.0.1:4000/v1,
# so its ranks keep resolving with no network at all), the server-nike
# gateway over Tailscale everywhere else:
# http://server-nike.bee-blues.ts.net:4000/v1.
#
# API keys are NOT stored here or in the nix store. They are read at runtime via
# opencode's `{file:...}` substitution from per-key files that the
# setupOpenCodeKeys activation script materializes out of
# /etc/secrets/opencode-keys.env (itself decrypted by agenix, see
# services/secrets.nix). The activation runs as the user, who can read that file
# through the `secrets` group. opencode uses litellm-proxy.key (the proxy's
# master key) for the gateway and the backend key files (zai, kimi, deepseek,
# hetzner, cheaperinference, unsloth) for the direct providers — the same
# files tools that talk to a provider directly already read (the systemone
# MCP reads unsloth.key). The strata providers carry the literal key
# "strata": Strata 0.2.18 requires Bearer STRATA_API_KEY, and that is the
# packages/strata apiKey default — the same value the proxy sends. A host
# that overrides strata.apiKey must update these literals too.
#
# Backends behind the proxy (the proxy config is the source of truth):
#   strata      http://laptop-p16.bee-blues.ts.net:8080/v1   (Strata on
#                  laptop-p16, and :8080 on server-nike for the local tiers;
#                  key: the literal `strata` (the STRATA_API_KEY default); the
#                  engine's served window is 262144 — `--max-context`
#                  written by `strata launch`, live `n_ctx` 262144 — the same
#                  window as the free-cloud tiers)
#   unsloth     http://127.0.0.1:8888/v1     (Unsloth Studio on the inference
#                  host; Studio enforces its own per-model context budget)
#   hetzner     https://inference.hetzner.com/v1             (free cloud; the
#                  official docs' base URL is the `/api/v1` variant — 2026-11-21
#                  probe: both routes live, 401 without a key)
#   deepseek    https://api.deepseek.com                     (V4 flash/pro: 1M ctx,
#                  384K out)
#   z.ai/GLM    https://api.z.ai/api/coding/paas/v4          (GLM Coding Plan
#                  subscription; NOT the pay-per-token endpoint
#                  https://api.z.ai/api/paas/v4/ — a coding-plan key is rejected
#                  there and never draws the subscription quota)
#   Kimi        https://api.kimi.com/coding/v1               (Kimi Code on the
#                  legacy Allegretto plan: every coding-plan model id is entitled
#                  there, and 1M context on k3.1-pro / k3 is Allegretto's tier;
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

  # The proxy gateway this host's opencode/pi talk to. laptop-p16 runs its own
  # litellm-proxy instance (services/litellm-proxy.nix, same config as
  # server-nike) on NixOS, so its clients use the local proxy and the rank
  # names keep resolving with no network at all (Strata answers on loopback).
  # The CachyOS install of p16 (the live one today) has no NixOS proxy
  # service, so it keeps the server-nike gateway over Tailscale like every
  # other host.
  proxyBaseURL =
    if hn == "laptop-p16" && ! config.commonHm.isCachyOS then
      "http://127.0.0.1:4000/v1"
    else
      "http://server-nike.bee-blues.ts.net:4000/v1";

  # Unsloth Studio on this host (every family host runs one per user; the
  # inference hosts run nicky's). Local loopback: Studio's keyless-localhost
  # access admits loopback requests, and the inference hosts keep the Studio
  # key matching the shared secret's key (the strataGpuHandoff hook reads the
  # same unsloth.key against the local Studio).
  studioBaseURL = "http://127.0.0.1:8888/v1";

  # System One Decision MCP — same Studio as studioBaseURL. On laptop-p16
  # (NixOS) the local Studio serves it, so the decision prompts stay on the
  # machine; everywhere else (CachyOS p16, server-nike) the server-nike
  # Studio endpoint is the proven path.
  systemoneMcpURL =
    if hn == "laptop-p16" && ! config.commonHm.isCachyOS then
      "http://127.0.0.1:8888/mcp/decisions/"
    else
      "http://server-nike.bee-blues.ts.net:8888/mcp/decisions/";

  # ---------------------------------------------------------------------------
  # ArtCraft "Crafting Apps" MCP servers (packages/craft-apps).
  #
  # Every Craft app ships <app>-cli with an `mcp` subcommand: a Model Context
  # Protocol server on stdio (JSON-RPC). It is headless by default — an
  # in-process engine, no window — so the agent works with the app closed, and
  # opencode starts the server itself when a session needs it. Guide:
  # https://craft.wiki/apps/connect-ai/overview/ ; per-app detail in each repo's
  # docs/mcp.md.
  #
  # File access is opt-in. On the apps that take automation roots, a direction
  # with no root grants NONE of that access, so the roots below are what makes
  # their file tools (open / save / export) usable at all. They point at the
  # agent's own workspace, ~/craft, with a dedicated output folder ~/craft/out:
  # the wiki's "give it a folder of its own to work in", and upstream's advice
  # to keep the write root a dedicated output folder rather than a whole
  # project — an agent holding a write root may replace files under it.
  # home.activation.setupCraftWorkspace creates the folders: a missing root is
  # a startup error for these servers, not a silent no-op. Add shared inputs
  # (photos, documents) by appending to craftReadRoots; keep craftWriteRoots
  # narrow.
  craftPkgs = import ../packages/craft-apps { pkgs = pkgs; };
  craftWorkspace = "${config.home.homeDirectory}/craft";
  craftReadRoots = [ craftWorkspace ];
  craftWriteRoots = [ "${craftWorkspace}/out" ];

  # Confinement flags per app, measured on the versions pinned in
  # packages/craft-apps (each CLI's `mcp --help`, plus a probe run):
  #   "automation" -> --automation-read-root DIR (repeatable) and
  #                    --automation-write-root DIR
  #   "short"      -> --read-root DIR and --write-root DIR (texturecraft,
  #                    materialcraft; the --automation-* spellings work there too)
  #   "none"       -> the CLI takes no confinement flags, so pass none:
  #                    filmcraft and gridcraft (no root options), cadcraft
  #                    (bridge to a running app only), lightcraft (its folder
  #                    argument is photos to import, not a limit), anicraft
  #                    (0.2.1 ignores unknown `mcp` flags — passing roots there
  #                    would read as confinement in the config and be none).
  craftRootArgs =
    roots:
    if roots == "automation" then
      (map (d: [ "--automation-read-root" d ]) craftReadRoots)
      ++ (map (d: [ "--automation-write-root" d ]) craftWriteRoots)
    else if roots == "short" then
      (map (d: [ "--read-root" d ]) craftReadRoots)
      ++ (map (d: [ "--write-root" d ]) craftWriteRoots)
    else
      [ ];

  # One opencode MCP server entry for a Craft app. `disabled = false` keeps it
  # in every session; set it true to hide one app's tool catalog.
  craftServer = app: { roots ? "automation", extraArgs ? [] }: {
    type = "local";
    command =
      [ "${craftPkgs.${app}}/bin/${app}-cli" "mcp" ]
      ++ extraArgs
      ++ flatten (craftRootArgs roots);
    disabled = false;
  };

  # The seventeen apps of https://getartcraft.com/apps, in the site's order.
  craftServers = mapAttrs (app: cfg: craftServer app cfg) {
    photocraft = { };
    vectorcraft = { };
    filmcraft = { roots = "none"; };
    # LightCraft works on a library, and a library opens in one program at a
    # time: a dedicated one keeps the agent out of the user's own library.
    lightcraft = {
      roots = "none";
      extraArgs = [ "--library" "${craftWorkspace}/library" ];
    };
    pdfcraft = { };
    effectcraft = { };
    anicraft = { roots = "none"; };
    designcraft = { };
    figcraft = { };
    texturecraft = { roots = "short"; };
    materialcraft = { roots = "short"; };
    soundcraft = { };
    wordcraft = { };
    deckcraft = { };
    cadcraft = { roots = "none"; };
    gridcraft = { roots = "none"; };
    # Craft Anything keeps its evidence, memory and journal in --project.
    # No --allow-run (tools that run code on this machine without asking), no
    # --deep, no --restricted: the defaults keep approvals with the person.
    craft-anything = {
      roots = "none";
      extraArgs = [ "--project" "${craftWorkspace}/craft-anything" ];
    };
  };

  # ---------------------------------------------------------------------------
  # Shared model cards — one definition per model, referenced by BOTH paths:
  # providers.proxy (the gateway's explicit ids and unranked pool) and the
  # direct per-backend providers below (see DIRECT PROVIDERS). Grouped by
  # backend, so a new model card lands on the gateway and on that backend's
  # direct provider in one edit. Rank association lives in the display name
  # (docs/ai-ranks.md); it stays accurate whichever path a call takes.
  # ---------------------------------------------------------------------------

  # Kimi Code (legacy Allegretto plan: all six ids are entitled, and the
  # 1M context on k3.1-pro / k3 is Allegretto's 1M tier).
  kimiModels = {
    "k3.1-pro" = {
      name = "k3.1-pro @ Kimi (Brigadier General)";
      reasoning = true;
      attachment = true;  # Kimi model table: image+video; live pixel test
      # 2026-11-17 on the K3.1 Pro line answered correctly
      limit = {
        context = 1048576;
        output = 131072;
      };
    };
    "k3" = {
      name = "k3 @ Kimi (Lieutenant Colonel)";
      reasoning = true;
      attachment = true;  # Kimi model table: image+video; live pixel tests
      # 2026-09 answered correctly
      limit = {
        context = 1048576;
        output = 131072;
      };
    };
    "k3-256k" = {
      name = "k3-256k @ Kimi (Lieutenant Colonel, 262K)";
      reasoning = true;
      attachment = true;  # Kimi model table: image only (no video)
      limit = {
        context = 262144;
        output = 131072;
      };
    };
    "kimi-for-coding" = {
      name = "kimi-for-coding @ Kimi (Major, K2.8)";
      reasoning = true;
      attachment = true;  # Kimi model table: image+video; live /v1/models
      # reports supports_image_in true and a live pixel test on this id
      # answered correctly (supersedes the old endpoint finding)
      limit = {
        context = 1048576;
        output = 131072;
      };
    };
  };

  # Z.ai Coding Plan (subscription quota, coding endpoint only).
  zaiModels = {
    "glm-5.3" = {
      name = "glm-5.3 @ Z.ai Coding Plan (Lieutenant Colonel)";
      reasoning = true;
      # GLM-5.3 is text-only by provider spec.
      limit = {
        context = 1000000;
        output = 131072;
      };
    };
    "glm-5.3-flash" = {
      name = "glm-5.3-flash @ Z.ai Coding Plan (Major)";
      reasoning = true;
      attachment = true;  # the GLM-5.3 series' multimodal line
      limit = {
        context = 1000000;
        output = 131072;
      };
    };
    "glm-5-turbo" = {
      name = "glm-5-turbo @ Z.ai Coding Plan (Captain Commandant)";
      reasoning = true;
      limit = {
        context = 200000;
        output = 131072;
      };
    };
  };

  # DeepSeek API (pay-per-token).
  deepseekModels = {
    "deepseek-flash" = {
      name = "deepseek-flash (Captain)";
      reasoning = true;
      attachment = true;
      limit = {
        context = 1048576;
        output = 393216;
      };
    };
    "deepseek-v4-pro" = {
      name = "deepseek-v4-pro (Captain Commandant / Major)";
      reasoning = true;
      limit = {
        context = 1048576;
        output = 393216;
      };
    };
  };

  # Hetzner free cloud (the two cloud deployments the ladder fronts,
  # under their own upstream ids; explicit selection).
  # Same two serving deployments as warrant-officer / second-lieutenant:
  # the endpoint answers the org-prefixed and the bare id of each model,
  # so all four ids are listed. Asking for one of these names means
  # asking for Hetzner — no local Strata failover (warrant-officer keeps
  # that), no cross-rank fallback, free tier so no cost.
  hetznerModels = {
    "Qwen/Qwen3.6-35B-A3B" = {
      name = "Qwen3.6-35B-A3B @ Hetzner (Warrant Officer, free cloud)";
      limit = {
        context = 262144;
        output = 32768;
      };
    };
    "Qwen/Qwen3.6-35B-A3B-FP8" = {
      name = "Qwen3.6-35B-A3B-FP8 @ Hetzner (Warrant Officer, free cloud)";
      limit = {
        context = 262144;
        output = 32768;
      };
    };
    "Qwen/Qwen3.8-27B" = {
      name = "Qwen3.8-27B @ Hetzner (Second Lieutenant, free cloud)";
      limit = {
        context = 262144;
        output = 32768;
      };
    };
    "Qwen3.8-27B" = {
      name = "Qwen3.8-27B @ Hetzner (Second Lieutenant, free cloud)";
      limit = {
        context = 262144;
        output = 32768;
      };
    };
  };

  # Unranked pay-as-you-go pool (CheaperInference only; explicit selection).
  # No model of the four ranked providers is unranked; this pool is the
  # reseller's OpenAI/Anthropic catalogue plus glm-5.3-payg, the cash twin
  # of the Coding Plan's glm-5.3.
  cheaperModels = {
    "deepseek-v4.1-flash" = {
      name = "deepseek-v4.1-flash (paid, CI: Captain's model at 56% off)";
      reasoning = true;
      attachment = true;
      limit = {
        context = 1048576;
        output = 393216;
      };
    };
    "gpt-5.6-luna" = {
      name = "gpt-5.6-luna (paid escalation, CI)";
      reasoning = true;
      attachment = true;
      limit = {
        context = 1050000;
        output = 128000;
      };
    };
    "claude-sonnet-5.5" = {
      name = "claude-sonnet-5.5 (paid escalation, CI)";
      reasoning = true;
      attachment = true;
      limit = {
        context = 1000000;
        output = 128000;
      };
    };
    "claude-opus-5.5" = {
      name = "claude-opus-5.5 (paid escalation, CI)";
      reasoning = true;
      attachment = true;
      limit = {
        context = 1000000;
        output = 128000;
      };
    };
    "glm-5.3-payg" = {
      name = "glm-5.3-payg (paid, per-token, CI)";
      reasoning = true;
      limit = {
        context = 1000000;
        output = 131072;
      };
    };
  };

  # The single resident Strata model, loaded on both engines (one model per
  # engine — a swap costs a full load; see docs/litellm-proxy-design.md
  # "Local model policy"). `strata launch` writes --max-context 262144 and
  # the live GET /v1/models reports n_ctx 262144 on both hosts. Output 65536
  # sits inside the shared window, same as the lieutenant rank card.
  strataModels = {
    "swift-1.5-iq3_xxs" = {
      name = "swift-1.5-iq3_xxs @ Strata (local engine)";
      attachment = true;  # the same weights serve the proxy's lieutenant-v
      # vision slot (pixel tests passed; live /v1/models reports
      # input_modalities text+image), so the direct path keeps a vision slot
      # while the gateway is down
      limit = {
        context = 262144;
        output = 65536;
      };
    };
  };

  # Unsloth Studio on server-nike — the sergeant rank's order-2 tier, kept as
  # a last-resort direct path (a Studio call costs a model load). Studio
  # serves the GGUF under the id the proxy fronts; the proxy records its
  # per-model context budget as 128256.
  unslothModels = {
    "unsloth/NVIDIA-Nemotron-3.5-Bolt-E4B-GGUF" = {
      name = "NVIDIA-Nemotron-3.5-Bolt-E4B @ Unsloth Studio (sergeant order-2)";
      limit = {
        context = 128256;
        output = 65536;
      };
    };
  };

  # Provider/model definitions shared by opencode and pi.
  #
  # Primary provider: the LiteLLM rank gateway (services/litellm-proxy.nix,
  # on server-nike). The proxy fronts every backend; its config carries the
  # deployment order, fallbacks, timeouts and cost tracking (see
  # docs/litellm-proxy-design.md). This table only carries display names, the
  # researched context/output limits (opencode compacts at limit.context) and
  # the modality flags (consumed by pi).
  #
  # Alongside it, one DIRECT provider per backend exposes the same models
  # without the gateway (see DIRECT PROVIDERS inside `providers` below), so
  # an outage of server-nike, the litellm unit or the Tailscale path never
  # leaves the harnesses without a model.
  #
  # Name classes on the proxy provider, in the order they appear below:
  #   1. rank names (the ladder in docs/ai-ranks.md). A rank is a pure
  #      abstraction over the model holding the slot: multiple models may share
  #      a rank, so a model swap never touches this file;
  #   2. explicit model names — one per ranked model, spelled exactly like the
  #      upstream id, merged in from the shared card bindings above;
  #   3. the unranked pay-as-you-go pool (CheaperInference + glm-5.3-payg),
  #      also from a shared binding.
  # Only -v ranks and the model ids whose model really sees images carry
  # `attachment = true`; plain ranks stay text-only by contract.
  providers = {
    proxy = {
      package = "aisdk:@ai-sdk/openai-compatible";
      settings = {
        baseURL = proxyBaseURL;
        apiKey = keyfile "litellm-proxy";
      };
      models = {
        # --- rank ladder: every model of the ranked providers holds a rank slot
        #     (subscription order -> pay-per-token -> free cloud -> local) -----
        "sergeant" = {
          name = "Sergeant — fast executor";
          # order 1 = Strata on server-nike (n_ctx 262144, the served window);
          # order 2 = Studio Nemotron (128256) when the Strata engine cannot
          # answer. Output 65536 sits inside both windows (prompt and
          # generation share one n_ctx), same as lieutenant.
          limit = {
            context = 262144;
            output = 65536;
          };
        };
        "warrant-officer" = {
          name = "Warrant Officer — workhorse (free cloud, local fallback)";
          # Text-only rank; the vision slot is warrant-officer-v.
          # Both deployments hold 262144 (Hetzner and the local Strata
          # fallback), so the group has one window.
          limit = {
            context = 262144;
            output = 32768;
          };
        };
        "warrant-officer-v" = {
          name = "Warrant Officer (vision) — multimodal workhorse";
          attachment = true;  # both deployments see images; the -v slot carries
                              # the vision contract
          limit = {
            context = 262144;
            output = 32768;
          };
        };
        "second-lieutenant" = {
          name = "Second Lieutenant — free-cloud reasoning";
          # Both deployments hold 262144 (Hetzner and the local Strata
          # fallback), so the group has one window.
          limit = {
            context = 262144;
            output = 32768;
          };
        };
        "lieutenant" = {
          name = "Lieutenant — deep reasoning (default)";
          reasoning = true;
          # Text-only rank; the vision slot is lieutenant-v (same model).
          # Context is the window the engine actually SERVES, not what the model
          # can do natively: `strata launch` writes --max-context 262144 into the
          # run config, and live `GET :8080/v1/models` reports n_ctx 262144 on
          # both hosts. The 384K the model supports natively is not what these
          # cards serve.
          # Output 65536 sits INSIDE that window: the engine's 262144 is one
          # shared n_ctx (prompt and generation come out of the same capacity),
          # so a full 65536-token answer only fits a short prompt, and a long
          # prompt leaves proportionally less.
          limit = {
            context = 262144;
            output = 65536;
          };
        };
        "lieutenant-v" = {
          name = "Lieutenant (vision) — deep reasoning, multimodal";
          reasoning = true;
          attachment = true;  # same model as lieutenant; the -v slot carries vision
          # Same deployment, same served window as `lieutenant` (see above).
          limit = {
            context = 262144;
            output = 65536;
          };
        };
        "captain" = {
          name = "Captain — cheap fast coding (DeepSeek, paid)";
          reasoning = true;
          # Text-only rank (deepseek-flash); the vision slot is captain-v.
          limit = {
            context = 1048576;
            output = 393216;
          };
        };
        "captain-v" = {
          name = "Captain (vision) — cheap fast coding, multimodal (paid)";
          reasoning = true;
          attachment = true;  # deepseek-flash: input_modalities [text, image]
          limit = {
            context = 1048576;
            output = 393216;
          };
        };
        "captain-commandant" = {
          name = "Captain Commandant — mid paid coding (Z.ai, then DeepSeek)";
          reasoning = true;
          # No -v sibling: glm-5-turbo and deepseek-v4-pro are both text-only.
          # Group max: the Z.ai row serves 200K, deepseek-v4-pro 1M, so the
          # pre-call check keeps a long prompt on the DeepSeek deployment.
          limit = {
            context = 1048576;
            output = 393216;
          };
        };
        "major" = {
          name = "Major — strong coding, not frontier (paid)";
          reasoning = true;
          # Deployments: kimi-for-coding (K2.8) -> glm-5.3-flash -> deepseek-v4-pro.
          # Text-only by rank contract (plain rank): all three deployments are
          # image-capable, but images are addressed to major-v.
          limit = {
            context = 1048576;
            output = 131072;
          };
        };
        "major-v" = {
          name = "Major (vision) — strong coding, multimodal (paid)";
          reasoning = true;
          attachment = true;  # kimi-for-coding (K2.8, image+video) then
          # glm-5.3-flash (Z.ai multimodal line, 3x quota)
          limit = {
            context = 1048576;
            output = 131072;
          };
        };
        "lieutenant-colonel" = {
          name = "Lieutenant Colonel — frontier coding (paid)";
          reasoning = true;
          # Deployments: glm-5.3 @ Z.ai -> k3 -> k3-256k @ Kimi.
          # Group max: k3 serves 1,048,576; glm-5.3 1M; k3-256k 262K.
          limit = {
            context = 1048576;
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
        "brigadier-general" = {
          name = "Brigadier General — k3.1-pro flagship (paid)";
          reasoning = true;
          # Text-only rank; the vision slot is brigadier-general-v. Thinking
          # cannot be disabled on k3.1-pro — the proxy pins reasoning_effort.
          limit = {
            context = 1048576;
            output = 131072;
          };
        };
        "brigadier-general-v" = {
          name = "Brigadier General (vision) — k3.1-pro multimodal (paid)";
          reasoning = true;
          attachment = true;  # Kimi model table: image+video; live test OK
          limit = {
            context = 1048576;
            output = 131072;
          };
        };

        # --- explicit model names + the unranked pay-as-you-go pool: the
        #     cards are merged in from the shared per-backend bindings above
        #     (kimiModels, zaiModels, deepseekModels, hetznerModels,
        #     cheaperModels). One card per model serves BOTH paths — these
        #     names on the gateway, and the same ids under the direct
        #     providers (see DIRECT PROVIDERS below) — so the two paths
        #     cannot drift.
      } // kimiModels // zaiModels // deepseekModels // hetznerModels
        // cheaperModels;
    };

    # -----------------------------------------------------------------------
    # DIRECT PROVIDERS — the same backends the proxy fronts, reachable
    # WITHOUT the LiteLLM gateway. The gateway is one service on one host:
    # if server-nike is down, its litellm unit fails, or the Tailscale path
    # is gone, every rank above is unreachable too. Each provider here talks
    # to the backend itself, with the key files setupOpenCodeKeys already
    # materializes for direct tools (and a literal key for Strata, which
    # accepts anything). Model cards are the shared *Models bindings above:
    # one card per model serves both paths.
    #
    # Selection is explicit: neither opencode nor pi fails over across
    # providers, so when the gateway is down, switch in the model picker
    # (for example zai/glm-5.3, kimi/k3.1-pro, strata-p16/swift-1.5-iq3_xxs).
    # The provider name is the cost class: zai and kimi draw subscription
    # quota (the same plans the proxy's subscription deployments draw),
    # deepseek and cheaperinference are pay-per-token, hetzner is free
    # cloud, and the strata/unsloth engines are local hardware.
    #
    # Reasoning depth is not pinned here. The proxy pins reasoning_effort only
    # on glm-5.3 / glm-5.3-flash (max) and k3.1-pro (high); its other Kimi and
    # Z.ai deployments are unpinned. On the direct path the provider defaults
    # cover it: Z.ai GLM-5.3 / GLM-5.3-Flash always think (default max), Kimi
    # k3.1-pro cannot disable thinking (default high), and the unpinned ids
    # keep their provider defaults.
    # -----------------------------------------------------------------------

    # Z.ai Coding Plan — subscription quota; the coding endpoint only (a plan
    # key is rejected on the pay-per-token endpoint api.z.ai/api/paas/v4).
    zai = {
      package = "aisdk:@ai-sdk/openai-compatible";
      settings = {
        baseURL = "https://api.z.ai/api/coding/paas/v4";
        apiKey = keyfile "zai";
      };
      models = zaiModels;
    };

    # Kimi Code (legacy Allegretto plan) — same endpoint and ids the proxy
    # fronts, minus the gateway hop.
    kimi = {
      package = "aisdk:@ai-sdk/openai-compatible";
      settings = {
        baseURL = "https://api.kimi.com/coding/v1";
        apiKey = keyfile "kimi";
      };
      models = kimiModels;
    };

    # DeepSeek API — pay-per-token.
    deepseek = {
      package = "aisdk:@ai-sdk/openai-compatible";
      settings = {
        baseURL = "https://api.deepseek.com";
        apiKey = keyfile "deepseek";
      };
      models = deepseekModels;
    };

    # Hetzner Inference — free cloud.
    hetzner = {
      package = "aisdk:@ai-sdk/openai-compatible";
      settings = {
        baseURL = "https://inference.hetzner.com/v1";
        apiKey = keyfile "hetzner";
      };
      models = hetznerModels;
    };

    # CheaperInference — wallet-backed pay-as-you-go pool.
    cheaperinference = {
      package = "aisdk:@ai-sdk/openai-compatible";
      settings = {
        baseURL = "https://api.cheaperinference.com/v1";
        apiKey = keyfile "cheaperinference";
      };
      models = cheaperModels;
    };

    # The two Strata engines, addressed directly. The proxy load-balances the
    # same pair behind swift-1.5; without it, pick an engine. Strata 0.2.18
    # requires Bearer STRATA_API_KEY; the literal "strata" below is the
    # packages/strata apiKey default — the same value the proxy sends.
    strata-nike = {
      package = "aisdk:@ai-sdk/openai-compatible";
      settings = {
        baseURL = "http://server-nike.bee-blues.ts.net:8080/v1";
        apiKey = "strata";
      };
      models = strataModels;
    };
    strata-p16 = {
      package = "aisdk:@ai-sdk/openai-compatible";
      settings = {
        baseURL = "http://laptop-p16.bee-blues.ts.net:8080/v1";
        apiKey = "strata";
      };
      models = strataModels;
    };

    # Unsloth Studio on this host — the sergeant rank's order-2 tier; a
    # last-resort direct path (a Studio call costs a model load).
    unsloth = {
      package = "aisdk:@ai-sdk/openai-compatible";
      settings = {
        baseURL = studioBaseURL;
        apiKey = keyfile "unsloth";
      };
      models = unslothModels;
    };
  };

  # pi (pi-coding-agent) reads ~/.pi/agent/models.json. It speaks the same
  # OpenAI-compatible endpoints, but a different schema: api/baseUrl instead of
  # npm/options.baseURL, and contextWindow/maxTokens instead of
  # limit.{context,output}. Its config is generated from `providers` above so
  # the two agents cannot drift apart.
  #
  # pi ships no native catalog for any of these providers (the rank gateway
  # and the direct backends all speak OpenAI-compatible HTTP), so every
  # provider is emitted as a full openai-completions definition.
  # `piNativeIds` stays empty.
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
  # native catalog for any provider defined here).
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
            # The custom zai/deepseek providers above shadow opencode's
            # built-in catalog entries with the same ids: Z.AI access is the
            # proxy's rank deployments (providers.proxy) or the direct zai
            # provider (the Coding Plan endpoint).
            # The Craft app servers (craftServers above) register on every host:
            # the apps are installed for all users (users/common-hm.nix) and run
            # locally with no GPU service or daemon behind them. Only the
            # inference-host servers stay gated.
            mcp = {
              servers = craftServers // optionalAttrs hasLocalInference {
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
                  url = systemoneMcpURL;
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
              }
              // optionalAttrs (pkgs ? rea) {
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
    # The Craft apps' MCP servers confine file access to ~/craft (read) and
    # ~/craft/out (write) — see craftWorkspace above. Those CLIs treat a missing
    # root as a startup error, not a silent no-op, so the folders must exist
    # before a session starts a server. Only the two roots are created here:
    # LightCraft's library/ and Craft Anything's craft-anything/ subfolders are
    # made by those CLIs on first use.
    home.activation.setupCraftWorkspace = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      export PATH="${pkgs.coreutils}/bin:$PATH"
      mkdir -p "${craftWorkspace}/out"
    '';

    home.activation.setupOpenCodeAIDeps = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      # Activation scripts run in a restricted environment; make sure PATH has
      # the tools this script needs.
      export PATH="${pkgs.coreutils}/bin:${pkgs.bun}/bin:$PATH"
      for dir in "${config.home.homeDirectory}/.node_modules" "${config.home.homeDirectory}/@opencode"; do
        ${pkgs.coreutils}/bin/mkdir -p "$dir"
        # --cwd must come after the subcommand: "bun --cwd <dir> install"
        # misparses "install" as a script name (bun 1.3).
        ${pkgs.bun}/bin/bun install --cwd "$dir" @opencode/ai 2>&1 || true
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
