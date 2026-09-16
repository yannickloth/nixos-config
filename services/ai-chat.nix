{ config, pkgs, ... }:

let
  # Compile the DB seeder at build time. SeedGates.java is a Java 25 compact
  # source file whose implicit class name is derived from the *file basename*;
  # the Nix store hash prefix would be an invalid class name, so copy it to
  # "SeedGates.java" before compiling.
  seedGates = pkgs.runCommand "open-webui-seed-gates" {
    nativeBuildInputs = [ pkgs.jdk25 ];
  } ''
    mkdir -p src "$out"
    cp ${./ai-chat/SeedGates.java} src/SeedGates.java
    javac -d "$out" src/SeedGates.java
  '';

  sqliteJdbc = "${pkgs.sqlite-jdbc}/share/java/sqlite-jdbc-${pkgs.sqlite-jdbc.version}.jar";
in
{
  # Family AI chat interface (Open WebUI) with OpenAI-compatible providers
  # (DeepSeek, Kimi for Coding, Hetzner AI).
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
    # The env file itself is decrypted by agenix (see services/secrets.nix);
    # only the shared secrets dir is created here.
    "d /etc/secrets 2770 root secrets -"
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
      OPENAI_API_BASE_URLS = ''["https://api.deepseek.com","https://api.kimi.com/coding/v1","https://inference.hetzner.com/api/v1","https://api.z.ai/api/paas/v4/"]'';
    };
    environmentFile = "/etc/secrets/open-webui.env"; # contains OPENAI_API_KEYS
  };

  # Keep the kid-safety gate in sync with the versioned source file. Open WebUI
  # reads filters from its DB at request time, so this runs after startup and is
  # a no-op whenever the file is unchanged.
  #
  # Explicit dependency: the seed service runs the compiled SeedGates class
  # (Java 25) via ${pkgs.jdk25}/bin/java with the sqlite-jdbc driver. Declaring
  # the JDK here keeps it in the system closure regardless of apps/java.nix.
  environment.systemPackages = [ pkgs.jdk25 ];
  systemd.services.open-webui-seed-gates = {
    description = "Seed the kid-safety filter into the Open WebUI database";
    wantedBy = [ "multi-user.target" ];
    after = [ "open-webui.service" ];
    serviceConfig = {
      Type = "oneshot";
      # Run as the same DynamicUser/namespace as open-webui so the SQLite DB
      # (and any -wal/-shm/journal files) are written as the same on-disk
      # owner. Running this as root created a root-owned webui.db that
      # open-webui's DynamicUser could not write, which broke open-webui at
      # boot.
      User = "open-webui";
      DynamicUser = true;
      PrivateUsers = true;
      StateDirectory = "open-webui";
      PrivateTmp = true;
      # Retry if the DB is not ready on first boot or a transient SQLite lock.
      Restart = "on-failure";
      RestartSec = "10";
      ExecStart = [
        [
          "${pkgs.jdk25}/bin/java"
          # sqlite-jdbc loads its native library via System.load (restricted in
          # JDK 24+); the flag silences the runtime warning.
          "--enable-native-access=ALL-UNNAMED"
          "--class-path"
          "${seedGates}:${sqliteJdbc}"
          "SeedGates"
          "${./ai-chat/filters/kid-safety.py}"
        ]
      ];
    };
  };
}
