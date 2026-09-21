# home-manager wrapper for the Laya package (see ./default.nix).
#
#   imports = [ ../../packages/laya/home.nix ];
#   laya.enable = true;   # e.g. gated on the host that has the CUDA venv
#
# Installs the launchers on PATH and runs the MCP server as a user service.
{ config, lib, pkgs, ... }:
with lib;
let
  cfg = config.laya;
in
{
  options.laya = {
    enable = mkEnableOption "Laya (System 1 decision engine) and its streamable-HTTP MCP server";

    package = mkOption {
      type = types.package;
      default = pkgs.callPackage ./default.nix { };
      defaultText = literalExpression "pkgs.callPackage ./default.nix { }";
      description = "The Laya package providing the launchers and MCP server.";
    };

    mcpPort = mkOption {
      type = types.port;
      default = 8765;
      description = "Loopback TCP port for the Laya MCP server.";
    };

    device = mkOption {
      type = types.nullOr types.str;
      default = null;
      example = "cuda";
      description = "Device to load checkpoints on (cuda, cpu, mps). null lets laya auto-detect.";
    };
  };

  config = mkIf cfg.enable {
    home.packages = [ cfg.package ];

    # Refresh an existing environment on switch, but never block a switch on a
    # first-run multi-GB download — the launchers handle that on demand.
    home.activation.layaSetup = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
      export UV_PROJECT_ENVIRONMENT="$HOME/.local/share/laya/venv"
      if [ -x "$UV_PROJECT_ENVIRONMENT/bin/python" ]; then
        $DRY_RUN_CMD ${cfg.package}/bin/laya-setup --quiet \
          || echo "warning: Laya environment refresh failed; run 'laya-setup' when online" >&2
      else
        echo "Laya: environment not created yet — run 'laya-setup' (first run downloads PyTorch/CUDA, several GB)."
      fi
    '';

    # Shared, GPU-resident MCP server (streamable HTTP, loopback only). MCP
    # clients connect as remote clients; the Router preloads the English and
    # multilingual checkpoints. The launcher no-ops (exit 0) if the venv is
    # missing, so this never triggers a multi-GB download on its own.
    systemd.user.services.laya-mcp = {
      Unit = {
        Description = "Laya MCP server (System 1 decision engine, streamable HTTP)";
        After = [ "network-online.target" ];
      };
      Install.WantedBy = [ "default.target" ];
      Service = {
        Type = "simple";
        ExecStart = "${cfg.package}/bin/laya-mcp";
        Environment = [ "LAYA_MCP_PORT=${toString cfg.mcpPort}" ]
          ++ optional (cfg.device != null) "LAYA_DEVICE=${cfg.device}";
        Restart = "on-failure";
        RestartSec = "15s";
      };
    };
  };
}
