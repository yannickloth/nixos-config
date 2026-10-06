# home-manager wrapper for the Orca package (see ./default.nix).
#
#   imports = [ ../../packages/orca/home.nix ];
#   orca.enable = true;                        # desktop client (GUI + CLI)
#   orca.server.enable = true;                 # always-on `orca serve` runtime
#
# The client is the Electron ADE and the `orca-ide` CLI. The server is the same
# binary run headless (`orca-ide serve`), kept alive by a systemd user service;
# other laptops' clients pair to it over Tailscale. A server needs the agent
# CLIs (opencode, ...) and their credentials installed under the SAME user that
# runs it — a client's logins do not carry over.
{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
let
  cfg = config.orca;

  # `orca serve` binds a WebSocket listener and advertises a reachable address
  # for clients. Derive the Tailscale IPv4 at start unless one is configured,
  # so the service does not hardcode an address that can change.
  serveLauncher = pkgs.writeShellScript "orca-serve-launch" ''
    set -eu
    addr='${if cfg.server.pairingAddress != null then cfg.server.pairingAddress else ""}'
    if [ -z "$addr" ] && command -v tailscale >/dev/null 2>&1; then
      addr="$(tailscale ip -4 2>/dev/null | ${pkgs.coreutils}/bin/head -n1 || true)"
    fi
    set -- --port ${toString cfg.server.port}
    if [ -n "$addr" ]; then
      set -- "$@" --pairing-address "$addr"
    else
      echo "orca: no Tailscale address found; clients must connect by IP/URL." >&2
    fi
    exec ${cfg.package}/bin/orca-ide serve "$@"
  '';
in
{
  options.orca = {
    enable = mkEnableOption "Orca (agent development environment: desktop client + orca-ide CLI)";

    package = mkOption {
      type = types.package;
      default = pkgs.orca;
      defaultText = literalExpression "pkgs.orca";
      description = "The Orca package (packages/orca/default.nix, via the ai-unstable overlay).";
    };

    server = {
      enable = mkEnableOption ''
        an always-on Orca runtime server (`orca-ide serve`) as a systemd user
        service. Keep it enabled on a single host; other clients pair to it.
        The unit runs under THIS user, so agent CLIs and their logins must be
        installed here (a client's credentials do not carry over).
      '';

      port = mkOption {
        type = types.port;
        default = 6768;
        description = "TCP port the Orca runtime server binds.";
      };

      pairingAddress = mkOption {
        type = types.nullOr types.str;
        default = null;
        example = "100.64.1.20";
        description = ''
          Address advertised to clients (a Tailscale IP, LAN host, or full
          wss:// URL). null derives the host's Tailscale IPv4 at start.
        '';
      };
    };
  };

  config = mkIf cfg.enable {
    home.packages = [ cfg.package ];

    # Register the client for pairing links (orca://pair?...) and the app menu.
    xdg.desktopEntries.orca = {
      name = "Orca";
      genericName = "Agent development environment";
      comment = "Run many coding agents in parallel git worktrees";
      exec = "${cfg.package}/bin/orca-ide %u";
      terminal = false;
      type = "Application";
      categories = [
        "Development"
        "IDE"
      ];
      mimeType = [ "x-scheme-handler/orca" ];
      settings.StartupWMClass = "orca";
    };

    systemd.user.services.orca-server = mkIf cfg.server.enable {
      Unit = {
        Description = "Orca runtime server (headless `orca serve`)";
        After = [ "network-online.target" ];
        Wants = [ "network-online.target" ];
      };
      Install = {
        WantedBy = [ "default.target" ];
      };
      Service = {
        Type = "simple";
        ExecStart = "${serveLauncher}";
        # Force software GL so the headless runtime's Chromium never contends
        # for the GPU that Unsloth/Strata use on laptop-p16.
        Environment = [ "LIBGL_ALWAYS_SOFTWARE=1" ];
        # KillMode=mixed lets Orca stop its own Xvfb child cleanly.
        KillMode = "mixed";
        Restart = "on-failure";
        RestartSec = "5s";
        # Exit 3 = another Orca instance already owns this userData profile.
        RestartPreventExitStatus = 3;
      };
    };

    # An always-on server must outlive logout, which needs lingering. On NixOS
    # the host sets users.users.<name>.linger = true; on the standalone CachyOS
    # deployment that lives in /etc, so enable it best-effort here (mirrors the
    # strataHostTuning pattern: never block a switch on an interactive sudo).
    home.activation.orcaServerLinger = mkIf cfg.server.enable (
      lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        if ! ${pkgs.systemd}/bin/loginctl show-user "$USER" -p Linger 2>/dev/null | ${pkgs.gnugrep}/bin/grep -q 'Linger=yes'; then
          if sudo -n true 2>/dev/null; then
            $DRY_RUN_CMD sudo loginctl enable-linger "$USER" || true
          else
            echo "orca: server needs lingering; run once: sudo loginctl enable-linger $USER" >&2
          fi
        fi
      ''
    );
  };
}
