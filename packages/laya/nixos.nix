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

    maxLen = mkOption {
      type = types.nullOr types.ints.positive;
      default = null;
      example = 8192;
      description = ''
        Override the checkpoint context window, in tokens. null keeps the
        checkpoint default (512 English / 1024 multilingual). The encoders
        state 8192 positions and use rotary embeddings, so they accept even
        more, but the decision heads were trained on 512/1024-token windows, so
        quality beyond the trained length is unvalidated (and cost grows
        quadratically).
      '';
    };
  };

  config = mkIf cfg.enable {
    environment.systemPackages = [ cfg.package ];

    # The unit runs as cfg.user:cfg.group. The default `laya` account owns the
    # venv (~/.local/share/laya/venv, under /var/lib/laya) and the model cache,
    # so provision it when the defaults are used; custom accounts must already
    # exist (asserted below).
    users.groups = mkIf (cfg.group == "laya") { laya = { }; };
    users.users = mkIf (cfg.user == "laya") {
      laya = {
        isSystemUser = true;
        group = cfg.group;
        home = "/var/lib/laya";
        createHome = true;
      };
    };

    assertions = [
      {
        assertion = cfg.user != "laya" || config.users.users ? laya;
        message = "services.laya.user '${cfg.user}' does not exist; set services.laya.user to a configured account.";
      }
      {
        assertion = cfg.group != "laya" || config.users.groups ? laya;
        message = "services.laya.group '${cfg.group}' does not exist; set services.laya.group to a configured group.";
      }
    ];

    systemd.services.laya-mcp = {
      description = "Laya MCP server (System 1 decision engine, streamable HTTP)";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        User = cfg.user;
        Group = cfg.group;
        ExecStart = "${cfg.package}/bin/laya-mcp";
        Environment = [ "LAYA_MCP_PORT=${toString cfg.mcpPort}" ]
          ++ optional (cfg.device != null) "LAYA_DEVICE=${cfg.device}"
          ++ optional (cfg.maxLen != null) "LAYA_MAX_LEN=${toString cfg.maxLen}";
        Restart = "on-failure";
        RestartSec = 15;
        # RestartSec default (100ms) limit window is 10s; with RestartSec=15
        # the start-limit could never trip and a crash loop would run forever.
        StartLimitIntervalSec = 120;
        StartLimitBurst = 5;
      };
    };
  };
}
