# NixOS wrapper for the Laya package (see ./default.nix).
#
#   imports = [ ../../packages/laya/nixos.nix ];
#   services.laya = {
#     enable = true;
#     user = "nicky";   # owns the venv (~/.local/share/laya/venv) and HF cache
#   };
#
# The venv and model checkpoints are per-user and created at runtime: run
# `laya-setup` as `services.laya.user` before (or let the first call do it).
{ config, lib, pkgs, ... }:
with lib;
let
  cfg = config.services.laya;
in
{
  options.services.laya = {
    enable = mkEnableOption "Laya (System 1 decision engine) streamable-HTTP MCP server";

    package = mkOption {
      type = types.package;
      default = pkgs.callPackage ./default.nix { };
      defaultText = literalExpression "pkgs.callPackage ./default.nix { }";
      description = "The Laya package providing the launchers and MCP server.";
    };

    user = mkOption {
      type = types.str;
      default = "laya";
      description = ''
        User the MCP server runs as. It owns the uv virtualenv
        (~/.local/share/laya/venv) and the model cache, so run `laya-setup` as
        this user once before the service can start.
      '';
    };

    group = mkOption {
      type = types.str;
      default = "laya";
      description = "Group the MCP server runs as.";
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
    environment.systemPackages = [ cfg.package ];

    systemd.services.laya-mcp = {
      description = "Laya MCP server (System 1 decision engine, streamable HTTP)";
      after = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        User = cfg.user;
        Group = cfg.group;
        ExecStart = "${cfg.package}/bin/laya-mcp";
        Environment = [ "LAYA_MCP_PORT=${toString cfg.mcpPort}" ]
          ++ optional (cfg.device != null) "LAYA_DEVICE=${cfg.device}";
        Restart = "on-failure";
        RestartSec = 15;
      };
    };
  };
}
