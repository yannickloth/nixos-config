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

  # Orca's agent skills are single-file guides (`skills/<name>/SKILL.md`) in the
  # Orca repo. Upstream installs them imperatively with `orca skills install`
  # (the community `npx skills` CLI): it clones the repo, needs network at
  # install time, and writes outside the Nix store. Install them declaratively
  # instead — pin each file to the release tag matching the packaged version and
  # verify it against the SHA-256 the app itself bundles in
  # resources/skills/current-manifest.json. `orca skills list` shows the set.
  #
  # Update: bump skillRev to the new `v<version>` tag (== default.nix version)
  # and refresh skillHashes from that release's manifest.
  skillRev = "v1.4.221";

  skillHashes = {
    "computer-use" = "sha256-KDmTP9NSFoRUYUZkA+YGFIgAX231cSbQzQ92nqRXU/M=";
    "linear-tickets" = "sha256-4YH4YHPaZcSSNhRp1QT+FeeuYbyZmQvEG+pHqhNFVhk=";
    "orca-cli" = "sha256-qnb4ZQUBAJbo6p7doXBaeKrnr0XlRIXz/gRgZkwdnko=";
    "orca-emulator" = "sha256-PacZEXnkbLDhpqk28etUJU9umOw4hJ4clfDhEHMHa0g=";
    "orca-emulator-android" = "sha256-Ot5Ob48nF8qJn9hB5h8RaWOkBulScBW4A4VMFtAS4ng=";
    "orca-linear" = "sha256-jaI++WRwkGMVys6P+E+AViVe430bLV24TYt7MnCgug8=";
    "orca-per-workspace-env" = "sha256-wAXRJqE9KRM1FHLwdpDxwaZg1PKG4qXyGGSu4pT0Ns4=";
    "orchestration" = "sha256-zRs2S/NXgbrQa/dasXZq+o1s7GnLIGBSlpHYmHGiCYo=";
  };

  skillFile = name: hash:
    pkgs.fetchurl {
      url = "https://raw.githubusercontent.com/stablyai/orca/${skillRev}/skills/${name}/SKILL.md";
      inherit hash;
    };

  # One store directory per skill, so each install target is a single symlink —
  # the same shape `npx skills add` produces.
  skillDir = name: pkgs.runCommand "orca-skill-${name}" { } ''
    install -Dm444 ${skillFile name skillHashes.${name}} $out/SKILL.md
  '';

  # The skills CLI fans a "universal" skill out to a shared dir plus per-agent
  # dirs for the agents it detects. Mirror that: `~/.agents/skills` is the
  # shared dir OpenCode/Cline/Pi read, and Claude Code / Hermes Agent get their
  # own `skills/`.
  skillAgentDirs = [
    ".agents"
    ".claude"
    ".hermes"
  ];

  skillLinks = listToAttrs (
    concatMap
      (name:
        map (dir: nameValuePair "${dir}/skills/${name}" {
          source = skillDir name;
          force = true;
        }) skillAgentDirs)
      cfg.skills
  );
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

    skills = mkOption {
      type = types.listOf (types.enum (attrNames skillHashes));
      default = [
        "orca-cli"
        "computer-use"
        "orchestration"
      ];
      example = literalExpression ''[ "orca-cli" "orchestration" "computer-use" ]'';
      description = ''
        Orca skill guides to install declaratively into the agent skill
        directories (`~/.agents/skills` plus `~/.claude` and `~/.hermes`).
        Same set `orca skills install` would install; pinned to the packaged
        release and pre-verified, so no network or `npx` at activation.
      '';
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

    # The desktop entry and hicolor icons now ship inside the package itself
    # (default.nix extraInstallCommands). Upstream's file is `orca-ide.desktop`
    # — deliberately not `orca.desktop`, the GNOME Orca screen reader's id,
    # which shadows this entry because /usr/share outranks the profile in
    # XDG_DATA_DIRS. Here we only register that entry as the handler for the
    # `orca://pair?...` links the client advertises.
    xdg.mimeApps.enable = true;
    xdg.mimeApps.defaultApplications."x-scheme-handler/orca" = [ "orca-ide.desktop" ];

    # Declarative, offline install of the requested Orca skills (see skillLinks).
    home.file = skillLinks;

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
