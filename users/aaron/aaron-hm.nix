{ config, pkgs, ... }:

{
  imports = [
    ../common-hm.nix
    ../emacs-kid.nix
    ../kid-firefox-policies.nix
    ../natural-scroll.nix
  ];

  home = {
    username = "aaron";
    homeDirectory = "/home/aaron";
    packages = with pkgs; [
      extremetuxracer # high-speed arctic penguin racing game
      gcompris # educational game suite for young children
      klavaro # full-featured touch typing tutor
      kdePackages.ktuberling # fun "potato head" constructor game for young kids
      lutris # game library manager / launcher
      luanti # open-world Minecraft-style building game (formerly Minetest)
      neverball # tilt the ball through levels
      supertux # Mario-style platformer with Tux
      supertuxkart # Tux kart racing
      tuxpaint # kid-friendly drawing
      tuxtype # touch typing tutor for kids
    ];
    sessionVariables = {
      MOZ_ENABLE_WAYLAND = 1;
    };
  };

  # Point the XDG user dirs into aaron's syncthing folder (/sync/aaron via the
  # ~/sync symlink), mirroring nicky/aeiuno. KDE/Plasma and xdg-user-dirs pick
  # these up so Desktop/Documents/... are synced and backed up to nestor.
  # aaron has rw access to /sync/aaron via a named ACL (services/syncthing).
  xdg.configFile."user-dirs.dirs".force = true;

  xdg.userDirs = {
    createDirectories = false;
    enable = true;
    setSessionVariables = true; # keep legacy default
    desktop = "/home/aaron/sync/aaron/Desktop/";
    documents = "/home/aaron/sync/aaron/Documents/";
    download = "/home/aaron/sync/aaron/Downloads/";
    music = "/home/aaron/sync/aaron/Music/";
    pictures = "/home/aaron/sync/aaron/Pictures/";
    publicShare = "/home/aaron/sync/aaron/Public/";
    templates = "/home/aaron/sync/aaron/Templates/";
    videos = "/home/aaron/sync/aaron/Videos/";
  };

  programs = {
    firefox = {
      enable = true;
      configPath = "${config.xdg.configHome}/mozilla/firefox";
    };
  };
}
