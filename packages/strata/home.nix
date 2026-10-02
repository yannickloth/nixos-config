# home-manager wrapper for the Strata package (see ./default.nix).
#
#   imports = [ ../../packages/strata/home.nix ];
#   strata.enable = true;   # gated on the host with the CUDA GPU (laptop-p16)
#
# Installs `strata` (first-run setup + foreground start), `strata-chat` and
# `strata-server`. The first `strata` run asks the model/size/context questions
# and downloads the ~70-84 GB model into ~/.local/share/strata (override the
# directory with STRATA_HOME).
#
# `strata-server` is the always-on, ENGINE-OPTIONAL server behind the Unsloth
# Studio integration: it holds no model until a request arrives (Studio's
# Custom provider points at http://127.0.0.1:8080/v1), and frees the engine's
# ~55 GB of RAM and most of the 12 GB card again after STRATA_IDLE_UNLOAD
# seconds (default 300) without a request. Runs as a user service so Studio
# can reach it whenever; Studio's own models keep the GPU the rest of the time.
{ config, lib, pkgs, ... }:
with lib;
let
  cfg = config.strata;
in
{
  options.strata = {
    enable = mkEnableOption "Strata (local Qwen3.8-Flash-Next 125B MoE inference, OpenAI/Anthropic API on localhost)";

    package = mkOption {
      type = types.package;
      default = pkgs.callPackage ./default.nix { };
      defaultText = literalExpression "pkgs.callPackage ./default.nix { }";
      description = "The Strata package providing the engine and the setup/start wrappers.";
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
