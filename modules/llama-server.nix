{ config, pkgs, lib, ... }:

let
  cfg = config.services.llama-server;
in {
  options.services.llama-server = {
    enable = lib.mkEnableOption "llama.cpp HTTP API server with CUDA support";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.llama-cpp;
      description = "The llama-cpp package to use";
    };

    host = lib.mkOption {
      type = lib.types.str;
      default = "127.0.0.1";
      description = "Host address to bind to";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 8080;
      description = "Port to listen on";
    };

    modelsDir = lib.mkOption {
      type = lib.types.path;
      default = "/home/nicky/.local/share/llama-cpp/models";
      description = "Directory containing downloaded models";
    };

    model = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Model file to load (relative to modelsDir)";
    };

    gpuLayers = lib.mkOption {
      type = lib.types.int;
      default = 35;
      description = "Number of layers to offload to GPU";
    };

    ctxSize = lib.mkOption {
      type = lib.types.int;
      default = 4096;
      description = "Context window size";
    };

    threads = lib.mkOption {
      type = lib.types.int;
      default = 4;
      description = "Number of CPU threads";
    };

    extraArgs = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Extra arguments to pass to llama-server";
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.services.llama-server = {
      description = "llama.cpp HTTP API Server";
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" ];

      serviceConfig = {
        ExecStart = ''
          ${cfg.package}/bin/llama-server \
            --host ${cfg.host} \
            --port ${toString cfg.port} \
            --model ${cfg.modelsDir}/${cfg.model} \
            --n-gpu-layers ${toString cfg.gpuLayers} \
            --ctx-size ${toString cfg.ctxSize} \
            --threads ${toString cfg.threads} \
            ${lib.concatStringsSep " " cfg.extraArgs}
        '';
        Restart = "on-failure";
        User = "nicky";
        Group = "users";
      };
    };
  };
}
