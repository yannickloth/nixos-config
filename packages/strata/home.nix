# home-manager wrapper for the Strata package (see ./default.nix).
#
#   imports = [ ../../packages/strata/home.nix ];
#   strata.enable = true;   # gated on the host with the CUDA GPU (laptop-p16)
#
# Installs `strata` (first-run setup + foreground start), `strata-chat` and
# `strata-server`. The first `strata` run asks the model/size/context questions
# and downloads the ~70-84 GB model into ~/.local/share/strata (override the
# directory with STRATA_HOME). The engine policy below (context, KV format, rope
# scaling, VRAM reserve) overrides whatever setup answered, whenever a config is
# written or served.
#
# `strata-server` is the always-on, engine-optional server behind the Unsloth
# Studio integration (Studio's Custom provider points at
# http://127.0.0.1:8080/v1). It passes `--lazy` (upstream's replacement for the
# fork's removed `--no-preload`): it holds no model until a request arrives, then
# frees the ~55 GB of RAM and most of the 12 GB card again after
# STRATA_IDLE_UNLOAD seconds (default 300) without a request, reloading on the
# next one. Runs as a user service so Studio can reach it whenever; Studio's own
# models keep the GPU the rest of the time.
{ config, lib, pkgs, strataSrc, ... }:
with lib;
let
  cfg = config.strata;
in
{
  options.strata = {
    enable = mkEnableOption "Strata (local Qwen3.8-Flash-Next 125B MoE inference, OpenAI/Anthropic API on localhost)";

    package = mkOption {
      type = types.package;
      default = pkgs.callPackage ./default.nix {
        inherit strataSrc;
        inherit (cfg) context kv kvResident ropeScaling;
      };
      defaultText = literalExpression "pkgs.callPackage ./default.nix { inherit strataSrc; inherit (config.strata) context kv kvResident ropeScaling; }";
      description = "The Strata package providing the engine and the setup/start wrappers.";
    };

    context = mkOption {
      type = types.ints.positive;
      default = 524288;
      description = ''
        Engine KV/state capacity (`--max-context`). Past the model's trained
        262144 this also enables yarn rope scaling with factor
        `context / 262144` (524288 -> factor 2). Enforced on every Strata config
        the package writes or serves, so `strata --setup` cannot leave it at a
        different value.
      '';
    };

    kv = mkOption {
      type = types.enum [ "int8" "q4_0" "k8v4" "fp16" ];
      default = "int8";
      description = ''
        KV cache format (`--kv`). `k8v4` is the lowest-memory hybrid but cannot
        stream its KV, so `kvResident` is dropped for it.
      '';
    };

    kvResident = mkOption {
      type = types.ints.unsigned;
      default = 32768;
      description = ''
        Cells of each attention layer kept in VRAM; the rest of the KV cache
        lives in pinned RAM (`--kv-resident`, engine minimum 20480). 0 keeps the
        whole KV in VRAM. Costs ~13.7 KB of RAM per context token at 8-bit.
      '';
    };

    ropeScaling = mkOption {
      type = types.enum [ "yarn" "linear" "none" ];
      default = "yarn";
      description = "RoPE extension method used only when context > 262144 (`--rope-scaling`).";
    };

    autoStart = mkOption {
      type = types.bool;
      default = true;
      description = ''
        Start `strata-server` at login. The server itself is light (no engine
        until a request); it is what lets Unsloth Studio reach the 125B on
        demand. false leaves the unit installed but stopped: start it with
        `systemctl --user start strata`.
      '';
    };

    idleUnloadSeconds = mkOption {
      type = types.ints.positive;
      default = 300;
      description = ''
        Seconds without a request after which `strata-server` unloads the
        engine (freeing ~55 GB of RAM and most of the GPU). The next request
        starts it again (a minute or two).
      '';
    };

    port = mkOption {
      type = types.port;
      default = 8080;
      description = "Loopback port of the Strata API (the port Studio's Custom provider points at).";
    };

    defaultConfig = mkOption {
      type = types.str;
      default = "";
      example = "strata-iq2_xs.json";
      description = ''
        Config file (name under the Strata home, or an absolute path) that
        `strata-server` serves. "" lets the most recently written config win.
      '';
    };
  };

  config = mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.ropeScaling != "none" || cfg.context <= 262144;
        message = "strata.ropeScaling = \"none\" needs strata.context <= 262144: the engine refuses --rope-scale with no scaling past the trained context.";
      }
      {
        assertion = cfg.kvResident == 0 || cfg.kvResident >= 20480;
        message = "strata.kvResident must be 0 (whole KV in VRAM) or at least 20480 (the engine's --kv-resident minimum).";
      }
    ];

    home.packages = [ cfg.package ];

    systemd.user.services.strata = {
      Unit = {
        Description = "Strata server (engine loads on demand; Unsloth Studio's 125B endpoint)";
        After = [ "network-online.target" ];
      };
      Install = mkIf cfg.autoStart { WantedBy = [ "default.target" ]; };
      Service = {
        Type = "simple";
        ExecStart = "${cfg.package}/bin/strata-server";
        Environment = [
          "BROWSER=true" # never open a browser from the service
          "STRATA_PORT=${toString cfg.port}"
          "STRATA_IDLE_UNLOAD=${toString cfg.idleUnloadSeconds}"
        ] ++ optional (cfg.defaultConfig != "") "STRATA_CONFIG=${cfg.defaultConfig}";
        # MAP_HUGETLB for the expert arena is charged to RLIMIT_MEMLOCK.
        LimitMEMLOCK = "infinity";
        # No setup yet (no venv/config): exit cleanly with guidance instead of
        # restart-looping. startLimit* keeps a broken config from spinning.
        Restart = "on-failure";
        RestartSec = "10s";
        StartLimitIntervalSec = 0;
      };
    };
  };
}
