{ config, pkgs, ... }:

{
  # Family AI chat interface (Open WebUI) backed by the DeepSeek API.
  #
  # Secrets are NOT in this file or git. They live in /etc/secrets/open-webui.env
  # (outside the repo, group-writable by the 'secrets' group so nicky and aeiuno
  # can edit them without sudo), loaded via systemd EnvironmentFile. See
  # /etc/secrets/README.md for how to add multiple providers.
  #
  # Kid-safe content gates are versioned in git at services/ai-chat/filters/
  # kid-safety.py and seeded into the Open WebUI database by the
  # open-webui-seed-gates systemd service (see below).

  users.groups.secrets = {
    members = [ "aeiuno" "nicky" ]; # may edit AI-chat secrets without sudo
  };

  systemd.tmpfiles.rules = [
    # setgid + group rw so nicky/aeiuno can edit secrets without root.
    "d /etc/secrets 2770 root secrets -"
    "f /etc/secrets/open-webui.env 0660 root secrets -"
  ];

  # Versioned instructions for the secrets dir (symlinked into /etc/secrets).
  environment.etc."secrets/README.md".source = ./ai-chat/secrets-README.md;

  services.open-webui = {
    enable = true;
    openFirewall = false; # 127.0.0.1 only: the kids use this machine locally
    environment = {
      # OpenAI-compatible providers (non-secret; keys live in the env file).
      # Add more base URLs here, then add matching keys in /etc/secrets/open-webui.env
      # via OPENAI_API_KEYS (see /etc/secrets/README.md).
      OPENAI_API_BASE_URLS = ''["https://api.deepseek.com"]'';
    };
    environmentFile = "/etc/secrets/open-webui.env"; # contains OPENAI_API_KEYS
  };

  # Keep the kid-safety gate in sync with the versioned source file. Open WebUI
  # reads filters from its DB at request time, so this runs after startup and is
  # a no-op whenever the file is unchanged.
  systemd.services.open-webui-seed-gates = {
    description = "Seed the kid-safety filter into the Open WebUI database";
    wantedBy = [ "multi-user.target" ];
    after = [ "open-webui.service" ];
    path = [ pkgs.python3 ];
    serviceConfig = {
      Type = "oneshot";
      # Retry if the DB is not ready on first boot or a transient SQLite lock.
      Restart = "on-failure";
      RestartSec = "10";
      ExecStart = [
        "${pkgs.python3}/bin/python3 ${./ai-chat/seed_gates.py} ${./ai-chat/filters/kid-safety.py}"
      ];
    };
  };
}
