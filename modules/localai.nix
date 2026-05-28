# LocalAI configuration module
# Provides OpenAI-compatible API server with CUDA support
{
  config,
  pkgs,
  lib,
  ...
}:

{
  home.activation.setupLocalai = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    # Create LocalAI directories
    $DRY_RUN_CMD mkdir -p "$HOME/.local/share/localai/models"
    $DRY_RUN_CMD mkdir -p "$HOME/.local/share/localai/data"

    # Download LocalAI binary if not exists
    if [ ! -f "$HOME/.local/bin/local-ai" ]; then
      echo "Downloading LocalAI binary..."
      $DRY_RUN_CMD ${pkgs.curl}/bin/curl -fsSL https://github.com/mudler/LocalAI/releases/latest/download/local-ai-v4.2.6-linux-amd64 -o "$HOME/.local/bin/local-ai"
      $DRY_RUN_CMD chmod +x "$HOME/.local/bin/local-ai"
      echo "LocalAI binary installed to $HOME/.local/bin/local-ai"
    fi
  '';

  home.sessionVariables = {
    LOCALAI_MODELS_PATH = "${config.home.homeDirectory}/.local/share/localai/models";
    LOCALAI_DATA_PATH = "${config.home.homeDirectory}/.local/share/localai/data";
  };

  systemd.user.services = {
    # LocalAI service (OpenAI-compatible API server with CUDA support - local binary)
    localai = {
      Unit = {
        Description = "LocalAI OpenAI-compatible API server (local binary)";
        After = [ "network-online.target" ];
      };
      Install = {
        WantedBy = [ "default.target" ];
      };
      Service = {
        ExecStart = "%h/.local/bin/local-ai run --models-path %h/.local/share/localai/models --data-path %h/.local/share/localai/data --address=127.0.0.1:8082 --f16 --max-active-backends=1 --enable-memory-reclaimer --memory-reclaimer-threshold=0.8";
        WorkingDirectory = "%h/.local/share/localai";
        Restart = "on-failure";
        RestartSec = "10s";
        Environment = [
          "CUDA_VISIBLE_DEVICES=0"
          "LD_LIBRARY_PATH=/opt/cuda/lib64:/usr/lib:/usr/lib64:/usr/lib/nvidia"
          "LOCALAI_ADDRESS=127.0.0.1:8082"
          "LOCALAI_MODELS_PATH=%h/.local/share/localai/models"
          "LOCALAI_DATA_PATH=%h/.local/share/localai/data"
          "LOCALAI_MAX_ACTIVE_BACKENDS=1"
          "LOCALAI_MEMORY_RECLAIMER=true"
          "LOCALAI_MEMORY_RECLAIMER_THRESHOLD=0.8"
        ];
      };
    };
  };
}