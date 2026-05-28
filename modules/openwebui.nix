# OpenWebUI configuration module
# Web interface for LLMs - configured to use LM Studio backend
{
  config,
  pkgs,
  lib,
  ...
}:

{
  systemd.user.services = {
    # OpenWebUI service (points to LM Studio)
    open-webui = {
      Unit = {
        Description = "OpenWebUI web interface (LM Studio backend)";
        After = [
          "network-online.target"
          "lm-studio.service"
        ];
        Wants = [ "lm-studio.service" ];
      };
      Install = {
        WantedBy = [ "default.target" ];
      };
      Service = {
        ExecStart = "${pkgs.open-webui}/bin/open-webui serve";
        Restart = "on-failure";
        RestartSec = "30s";
        Environment = [
          # LM Studio uses port 1234 by default
          "OPENAI_API_BASE_URL=http://localhost:1234/v1"
          "WEBUI_SECRET_KEY=nicky-secret-key"
          "DATA_DIR=${config.home.homeDirectory}/.local/share/open-webui/data"
        ];
      };
    };
  };
}