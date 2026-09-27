# home-manager wrapper for the CLM package (see ./default.nix).
#
#   imports = [ ../../packages/clm/home.nix ];
#   clm.enable = true;   # e.g. gated on the host that has the CUDA venv
#
# Installs the launchers on PATH, runs the Qwen3-8B pooling encoder
# (clm-encoder, GPU, :8090) and the CLM API server + playground
# (clm-serve, :8700) as systemd user services.
{ config, lib, pkgs, ... }:
with lib;
let
  cfg = config.clm;
in
{
  options.clm = {
    enable = mkEnableOption "CLM (Contrastive Language Models) and its encoder + API server services";

    package = mkOption {
      type = types.package;
      default = pkgs.callPackage ./default.nix { };
      defaultText = literalExpression "pkgs.callPackage ./default.nix { }";
      description = "The CLM package providing the launchers.";
    };

    port = mkOption {
      type = types.port;
      default = 8700;
      description = "Loopback TCP port for the CLM API server (clm-serve).";
    };

    enableEncoder = mkOption {
      type = types.bool;
      default = true;
      description = ''
        Run the Qwen3-8B pooling encoder as the clm-encoder user service. The
        encoder is the GPU-heavy half (~17 GB VRAM in bf16 plus the action
        cache, and a ~16 GB backbone download to the HF cache on first start).
        Disable it — and set embUrl — when a clm-encoder already runs on
        another (tailnet) host.
      '';
    };

    embPort = mkOption {
      type = types.port;
      default = 8090;
      description = "Loopback TCP port for the embedding encoder (clm-encoder).";
    };

    embHost = mkOption {
      type = types.str;
      default = "127.0.0.1";
      example = "0.0.0.0";
      description = "Bind address for the embedding encoder. 0.0.0.0 exposes it to the network (e.g. to serve other tailnet hosts).";
    };

    embUrl = mkOption {
      type = types.nullOr types.str;
      default = null;
      example = "http://somehost:8090/v1/embeddings";
      description = "Embeddings endpoint clm-serve scores against. null derives http://127.0.0.1:<embPort>/v1/embeddings.";
    };

    embModel = mkOption {
      type = types.str;
      default = "qwen3-8b";
      description = "Name the encoder serves its model under (must match what clm-serve requests).";
    };

    encoderModel = mkOption {
      type = types.str;
      default = "Qwen/Qwen3-8B";
      description = "Hugging Face model id for the pooling encoder.";
    };

    maxModelLen = mkOption {
      type = types.ints.positive;
      default = 2048;
      description = ''
        Context window in tokens, applied to both the encoder
        (--max-model-len) and clm-serve (--max-tokens); states longer than
        this are truncated. The README advises raising both limits together.
      '';
    };

    device = mkOption {
      type = types.nullOr types.str;
      default = null;
      example = "cpu";
      description = "Device for the CLM projection heads (cuda, cpu). null lets torch auto-detect.";
    };

    actionCache = mkOption {
      type = types.nullOr types.str;
      default = null;
      example = "0";
      description = ''
        Vector-arena size for clm-serve: a fraction of the device ("0.02",
        the upstream default), an absolute size ("512MiB"), or "0" to switch
        it off. null keeps the upstream default.
      '';
    };

    autoStart = mkOption {
      type = types.bool;
      default = false;
      description = ''
        Start the services automatically at login (WantedBy =
        default.target). false leaves the units installed but stopped —
        start them with `systemctl --user start clm-encoder clm-serve`. The
        encoder claims ~17 GB of VRAM while it runs, so this defaults to
        false to keep the GPU free for unsloth studio unless asked for.
      '';
    };
  };

  config = mkIf cfg.enable {
    home.packages = [ cfg.package ];

    # Refresh an existing environment on switch, but never block a switch on a
    # first-run multi-GB download — the launchers handle that on demand.
    home.activation.clmSetup = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
      export UV_PROJECT_ENVIRONMENT="$HOME/.local/share/clm/venv"
      if [ -x "$UV_PROJECT_ENVIRONMENT/bin/python" ]; then
        $DRY_RUN_CMD ${cfg.package}/bin/clm-setup --quiet \
          || echo "warning: CLM environment refresh failed; run 'clm-setup' when online" >&2
      else
        echo "CLM: environment not created yet — run 'clm-setup' (first run downloads torch/vLLM/CUDA, several GB)."
      fi
    '';

    systemd.user.services = {
      # The CLM API server (typed questions, ranking, playground). Tolerates a
      # not-yet-ready encoder: requests just return 502 until it is up.
      clm-serve = {
        Unit = {
          Description = "CLM API server (System 1 decision engine, typed questions + playground)";
          After = [ "network-online.target" ]
            ++ optional cfg.enableEncoder "clm-encoder.service";
          Wants = optional cfg.enableEncoder "clm-encoder.service";
        };
        Install = mkIf cfg.autoStart { WantedBy = [ "default.target" ]; };
        Service = {
          Type = "simple";
          ExecStart = escapeShellArgs [
            "${cfg.package}/bin/clm-serve"
            "--port"
            (toString cfg.port)
            "--max-tokens"
            (toString cfg.maxModelLen)
          ];
          Environment = [
            "CLM_EMB_MODEL=${cfg.embModel}"
          ]
          ++ optional (cfg.embUrl != null) "CLM_EMB_URL=${cfg.embUrl}"
          ++ optional (cfg.device != null) "CLM_DEVICE=${cfg.device}"
          ++ optional (cfg.actionCache != null) "CLM_ACTION_CACHE=${cfg.actionCache}";
          Restart = "on-failure";
          RestartSec = "15s";
        };
      };
    } // optionalAttrs cfg.enableEncoder {
      # The GPU encoder vLLM half. First start downloads the ~16 GB backbone
      # and takes minutes to load; clm-serve handles that window gracefully.
      clm-encoder = {
        Unit = {
          Description = "CLM embedding encoder (vLLM Qwen3-8B pooling, ${cfg.encoderModel})";
          After = [ "network-online.target" ];
        };
        Install = mkIf cfg.autoStart { WantedBy = [ "default.target" ]; };
        Service = {
          Type = "simple";
          ExecStart = "${cfg.package}/bin/clm-encode";
          Environment = [
            "CLM_ENCODER_MODEL=${cfg.encoderModel}"
            "CLM_EMB_MODEL=${cfg.embModel}"
            "CLM_EMB_HOST=${cfg.embHost}"
            "CLM_EMB_PORT=${toString cfg.embPort}"
            "CLM_MAX_MODEL_LEN=${toString cfg.maxModelLen}"
          ];
          Restart = "on-failure";
          RestartSec = "15s";
        };
      };
    };
  };
}
