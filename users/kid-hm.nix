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
{ config, pkgs, ... }:

{
  imports = [
    ./common-hm.nix
    ./emacs.nix
    ./kid-firefox-policies.nix
    ./natural-scroll.nix
  ];

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
}
