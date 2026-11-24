# Shared home configuration for the kids' accounts (sven, aaron).
#
# Both kid accounts import this file (users/sven/sven-hm.nix,
# users/aaron/aaron-hm.nix), so everything a kid gets is declared ONCE and the
# two accounts cannot drift apart — the same reason users/common-hm.nix exists.
# Each per-kid file keeps only the account identity plus that kid's own extras.
#
# The policy side is already symmetric and lives on the system: malcontent
# allowlist + the 06:00-22:00 session limit (services/malcontent.nix), the
# never-a-wheel-member assertion (security/kids.nix), the Tor port block
# (services/tor.nix), the kid Firefox policies (users/kid-firefox-policies.nix),
# the rw ACLs on /sync/<name>, /sync/FileDrop and the roms
# (services/syncthing/default.nix), and the /filedrop group (users/filedrop.nix).
#
# PKG RULE for kids — the office/creative/media/mail apps (LibreOffice, GIMP,
# Krita, VLC, Geary) are NOT listed here: they come as flatpaks
# (apps.flatpak.apps in environments/family-laptop.nix) precisely so malcontent
# can gate them without a rebuild. One source per user, never native + flatpak
# both (rule of thumb in users/readmes/parents.md). sven-hm.nix used to install
# libreoffice-qt6 next to the flatpak; that is why it is not here.
{ config, lib, pkgs, ... }:

{
  imports = [
    ./common-hm.nix
    ./emacs.nix
    ./kid-firefox-policies.nix
    ./natural-scroll.nix
    ./opencode.nix          # opencode + pi provider/model config (proxy gateway + direct backends)
  ];

  # Enable the shared opencode/pi provider/model config. Uses the default
  # /etc/secrets path on NixOS hosts (the system agenix secret is shared).
  opencode.enable = true;

  home.packages =
    with pkgs;
    [
      digikam # photo management / organizer
      extremetuxracer # high-speed arctic penguin racing game
      gcompris # educational game suite for young children
      google-chrome # web browser
      jetbrains-toolbox # JetBrains IDEs (IntelliJ, PyCharm, ...) via Toolbox
      kdePackages.dolphin # native file manager (ACL access to /filedrop; see users/filedrop.nix)
      kdePackages.ktuberling # fun "potato head" constructor game for young kids
      keepassxc # password manager
      klavaro # full-featured touch typing tutor
      lutris # game library manager / launcher
      luanti # open-world Minecraft-style building game (formerly Minetest)
      neverball # tilt the ball through levels
      opencode # AI coding agent harness (CLI)
      pi-coding-agent # pi: AI coding agent
      hermes-agent # hermes: AI coding agent with LiteLLM proxy routing
      python3 # the "learning to code" language the kid READMEs advertise
      racket # programming language, includes the DrRacket IDE (for learning to code)
      supertux # Mario-style platformer with Tux
      supertuxkart # Tux kart racing
      tuxpaint # kid-friendly drawing
      tuxtype # touch typing tutor for kids
    ];

  home.sessionVariables = {
    MOZ_ENABLE_WAYLAND = "1";
  };

  # home-manager's fontconfig (defaults to NixOS fonts.fontconfig.enable) writes
  # this; force overwrite of a pre-existing unmanaged file. When the
  # fontconfig module is disabled (e.g. standalone home-manager on CachyOS)
  # the file doesn't exist, so the entry must be disabled too.
  xdg.configFile."fontconfig/conf.d/10-hm-fonts.conf" = {
    enable = config.fonts.fontconfig.enable;
    force = true;
  };

  # Point the XDG user dirs into the kid's own syncthing folder
  # (/sync/<name>, reached through the ~/sync symlink), mirroring nicky/aeiuno.
  # KDE/Plasma and xdg-user-dirs pick these up so Desktop/Documents/... are
  # synced and backed up to nestor. Each kid has rw on /sync/<name> through a
  # named ACL (services/syncthing/default.nix), so the paths are derived from
  # the account name here rather than repeated per kid.
  xdg.configFile."user-dirs.dirs".force = true;

  xdg.userDirs = {
    createDirectories = false;
    enable = true;
    setSessionVariables = true; # keep legacy default
    desktop = "${config.home.homeDirectory}/sync/${config.home.username}/Desktop/";
    documents = "${config.home.homeDirectory}/sync/${config.home.username}/Documents/";
    download = "${config.home.homeDirectory}/sync/${config.home.username}/Downloads/";
    music = "${config.home.homeDirectory}/sync/${config.home.username}/Music/";
    pictures = "${config.home.homeDirectory}/sync/${config.home.username}/Pictures/";
    projects = "${config.home.homeDirectory}/sync/${config.home.username}/Projects/";
    publicShare = "${config.home.homeDirectory}/sync/${config.home.username}/Public/";
    templates = "${config.home.homeDirectory}/sync/${config.home.username}/Templates/";
    videos = "${config.home.homeDirectory}/sync/${config.home.username}/Videos/";
  };

  programs = {
    firefox = {
      enable = true;
      configPath = "${config.xdg.configHome}/mozilla/firefox";
    };
  };

  # hermes-agent: route through the LiteLLM rank gateway on server-nike.
  # Same pattern as aeiuno/nicky but without the orca-status plugin (kids
  # don't need the runtime status plugin).
  home.activation.writeHermesConfig = lib.hm.dag.entryAfter [ "writeBoundary" "herdrIntegrations" "writeHermesEnv" ] ''
    if $DRY_RUN_CMD ${pkgs.yq}/bin/yq -e '.model.default' "$HOME/.hermes/config.yaml" >/dev/null 2>&1; then
      $DRY_RUN_CMD ${pkgs.yq}/bin/yq -iy '
        .model = {"default": "lieutenant", "provider": "proxy", "base_url": "http://server-nike.bee-blues.ts.net:4000/v1"}
      ' "$HOME/.hermes/config.yaml"
      # Gateway + direct subscription providers (idempotent: same-named
      # entries are replaced, unknown ones kept).
      $DRY_RUN_CMD ${pkgs.yq}/bin/yq -iy '
        .custom_providers = ((.custom_providers // []) | map(select(.name != "proxy" and .name != "zai-coding" and .name != "kimi-code"))) + [
          {"name": "proxy", "base_url": "http://server-nike.bee-blues.ts.net:4000/v1", "key_env": "LITELLM_MASTER_KEY", "model": "lieutenant", "models": {"lieutenant": {}}},
          {"name": "zai-coding", "base_url": "https://api.z.ai/api/coding/paas/v4", "key_env": "ZAI_CODING_API_KEY", "model": "glm-5.3", "models": {"glm-5.3": {}, "glm-5.3-flash": {}, "glm-5-turbo": {}}},
          {"name": "kimi-code", "base_url": "https://api.kimi.com/coding/v1", "key_env": "KIMI_CODE_API_KEY", "model": "k3.1-pro", "models": {"k3.1-pro": {}, "k3": {}, "k3-256k": {}, "kimi-for-coding": {}}}
        ]
      ' "$HOME/.hermes/config.yaml"
    else
      echo "hermes: config.yaml not yet present; skipping model override" >&2
    fi
  '';

  # hermes credential source: upsert gateway + subscription keys into
  # ~/.hermes/.env. Same source as opencode keys (system agenix path on
  # NixOS), so a rotation reaches hermes on the next switch too.
  home.activation.writeHermesEnv = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    $DRY_RUN_CMD ${pkgs.python3}/bin/python3 - "${config.home.homeDirectory}" '${config.opencode.envFile}' <<'PYEOF'
    import json, os, sys

    home = sys.argv[1]
    candidates = [os.path.expandvars(p) for p in (sys.argv[2], "/etc/secrets/opencode-keys.env") if p]
    envfile = next((p for p in candidates if p and os.path.exists(p)), None)
    env_path = os.path.join(home, ".hermes", ".env")
    mapping = {
        "http://server-nike.bee-blues.ts.net:4000/v1": "LITELLM_MASTER_KEY",
        "https://api.z.ai/api/paas/v4/": "ZAI_CODING_API_KEY",
        "https://api.z.ai/api/coding/paas/v4": "ZAI_CODING_API_KEY",
        "https://api.kimi.com/coding/v1": "KIMI_CODE_API_KEY",
    }
    managed = set(mapping.values())
    if envfile is None:
        print("hermes: no key source found (%s); skipping .env update" % ", ".join(candidates))
        sys.exit(0)
    try:
        with open(envfile) as fh:
            _, _, payload = fh.read().partition("=")
        keys = json.loads(payload.strip())
    except Exception as exc:
        print(f"hermes: failed to parse {envfile}: {exc}; leaving .env untouched", file=sys.stderr)
        sys.exit(0)
    values = {}
    for url, var in mapping.items():
        key = keys.get(url)
        if key:
            values[var] = key
    missing = sorted(managed - set(values))
    if missing:
        print(f"hermes: no secret key for {', '.join(missing)}; those vars not written")
    kept = []
    try:
        with open(env_path, encoding="utf-8") as fh:
            kept = [l.rstrip("\n") for l in fh if l.strip() and l.split("=", 1)[0] not in managed]
    except FileNotFoundError:
        os.makedirs(os.path.dirname(env_path), mode=0o700, exist_ok=True)
    for var in sorted(values):
        kept.append(f"{var}={values[var]}")
    fd = os.open(env_path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    os.fchmod(fd, 0o600)
    with os.fdopen(fd, "w") as out:
        if kept:
            out.write("\n".join(kept) + "\n")
    print(f"hermes: wrote {len(values)} key var(s) to {env_path}")
    PYEOF
  '';
}
