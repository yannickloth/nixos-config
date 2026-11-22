# Kintsugi-27B home-manager module.
#
#   imports = [ ../../packages/kintsugi-27b/home.nix ];
#   kintsugi-27b.enable = true;   # gated per host on a 12 GB CUDA card (laptop-p16, server-nike)
#
# One instance per host: the engine binds its own port, so it does not collide
# with Strata (:8080) or Unsloth Studio (:8888). Both inference hosts qualify:
# laptop-p16's RTX A3000 12GB (sm_86) and server-nike's RTX 3060 12GB (sm_86).
# Each host serves its own instance; clients point at http://127.0.0.1:<port>/v1.
# The engine is a llama.cpp fork with EXL3 trellis kernels — stock llama.cpp
# cannot load the model, so Unsloth Studio and Studio's container cannot serve
# it either. It needs its own engine binary (from the Kintsugi bundle) and its
# own CUDA runtime (bundled in bin/).
#
# The model file (10.5 GB GGUF) is fetched at build time. The runtime directory
# (~/.local/share/kintsugi-27b) holds the symlinked model and the engine's logs.
# The service starts in --wait mode (blocks until killed), yields to the desktop
# via ai.slice (CPUWeight 20, MemoryHigh 64G), and listens on the configured port.

{ config, lib, pkgs, ... }:
with lib;
let
  cfg = config.kintsugi-27b;
in
{
  # The `ai.slice` resource budget (see ../ai-slice.nix). Imported here so the
  # budget follows the package instead of one user's config.
  imports = [ ../ai-slice.nix ];

  options.kintsugi-27b = {
    enable = mkEnableOption "Kintsugi-27B (local Qwen3.8-27B inference, OpenAI-compatible API on localhost)";

    package = mkOption {
      type = types.package;
      default = pkgs.callPackage ./default.nix {
        # Pass isCachyOS from the home-manager build context.
        inherit (config.commonHm) isCachyOS;
      };
      defaultText = literalExpression "pkgs.callPackage ./default.nix { inherit (config.commonHm) isCachyOS; }";
      description = "The Kintsugi-27B package providing the engine, model, and launcher.";
    };

    port = mkOption {
      type = types.port;
      default = 9931;
      description = "TCP port for the OpenAI-compatible API. The bundle's llama.cpp fork uses this for serving.";
    };

    host = mkOption {
      type = types.str;
      default = "127.0.0.1";
      description = ''
        Address the Kintsugi-27B API listens on. Loopback by default — the server
        is for this machine's clients (opencode, Pi, Claude Code). Set to 0.0.0.0
        where the host firewall scopes the exposure.
      '';
      example = "0.0.0.0";
    };

    autoStart = mkOption {
      type = types.bool;
      default = true;
      description = ''
        Start the Kintsugi-27B server at login. false leaves the unit installed
        but stopped: start it with `systemctl --user start kintsugi-27b`.
      '';
    };

    # Extra arguments passed to the engine (KINTSUGI_EXTRA env var).
    extraArgs = mkOption {
      type = types.str;
      default = "";
      description = "Additional command-line arguments to pass to the engine (via KINTSUGI_EXTRA).";
    };

    # K/V cache type: q4_0 (default), q8_0, q3_0.
    kvType = mkOption {
      type = types.enum [ "q4_0" "q8_0" "q3_0" ];
      default = "q4_0";
      description = "K/V cache quantization. Affects VRAM usage and speed.";
    };

    # Context window in tokens (default 262144).
    context = mkOption {
      type = types.ints.unsigned;
      default = 262144;
      description = "Context window in tokens. The bundle defaults to 262144.";
    };
  };

  config = mkIf cfg.enable {
    home.packages = [ cfg.package ];

    # Environment variables forwarded to start-server.sh (KINTSUGI_* prefix).
    # Set unconditionally (not gated on autoStart) so manual invocations from
    # the terminal also pick them up. The wrapper sets LD_LIBRARY_PATH for the
    # bundled CUDA runtime + driver libs.
    home.sessionVariables = {
      KINTSUGI_PORT = toString cfg.port;
      KINTSUGI_HOST = cfg.host;
      KINTSUGI_KV = cfg.kvType;
      KINTSUGI_CTX = toString cfg.context;
    } // lib.optionalAttrs (cfg.extraArgs != "") {
      KINTSUGI_EXTRA = cfg.extraArgs;
    };

    systemd.user.services.kintsugi-27b = {
      Unit = {
        Description = "Kintsugi-27B local inference server (Qwen3.8-27B at 2.47 bits, ${toString cfg.context} context)";
        After = [ "network-online.target" ];
        StartLimitIntervalSec = 0;
      };
      Install = mkIf cfg.autoStart {
        WantedBy = [ "default.target" ];
      };
      Service = {
        Type = "simple";
        # ai.slice: CPUWeight 20, MemoryHigh 64G (packages/ai-slice.nix).
        # Yields CPU and memory to the desktop session while running.
        Slice = "ai.slice";
        Nice = 10;
        IOSchedulingClass = "best-effort";
        IOSchedulingPriority = 7;
        ExecStart = "${cfg.package}/bin/kintsugi-27b";
        Environment = [
          "KINTSUGI_PORT=${toString cfg.port}"
          "KINTSUGI_HOST=${cfg.host}"
          "KINTSUGI_KV=${cfg.kvType}"
          "KINTSUGI_CTX=${toString cfg.context}"
        ] ++ lib.optionals (cfg.extraArgs != "") [
          "KINTSUGI_EXTRA=${cfg.extraArgs}"
        ];
        Restart = "on-failure";
        RestartSec = "10s";
      };
    };
  };
}
