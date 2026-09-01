{ config, pkgs, ... }:

{
  imports = [
    ../common-hm.nix
    ../emacs-kid.nix
    ../kid-firefox-policies.nix
    ../natural-scroll.nix
  ];

  home = {
    username = "sven";
    homeDirectory = "/home/sven";
    packages = with pkgs; [
      audacious # light music player
      digikam # photo management / organizer
      extremetuxracer # high-speed arctic penguin racing game
      gcompris # educational game suite for young children
      klavaro # full-featured touch typing tutor
      kdePackages.ktuberling # fun "potato head" constructor game for young kids
      lutris # game library manager / launcher
      luanti # open-world Minecraft-style building game (formerly Minetest)
      neverball # tilt the ball through levels
      racket # programming language, includes the DrRacket IDE (for learning to code)
      jetbrains-toolbox # JetBrains IDEs (IntelliJ, PyCharm, ...) via Toolbox
      supertux # Mario-style platformer with Tux
      supertuxkart # Tux kart racing
      tuxpaint # kid-friendly drawing
      tuxtype # touch typing tutor for kids
    ];
    sessionVariables = {
      MOZ_ENABLE_WAYLAND = 1;
    };
  };

  # home-manager's fontconfig (defaults to NixOS fonts.fontconfig.enable) writes
  # this; force overwrite of a pre-existing unmanaged file. When the
  # fontconfig module is disabled (e.g. standalone home-manager on CachyOS)
  # the file doesn't exist, so the entry must be disabled too.
  xdg.configFile."fontconfig/conf.d/10-hm-fonts.conf" = {
    enable = config.fonts.fontconfig.enable;
    force = true;
  };

  programs = {
    firefox = {
      enable = true;
      configPath = "${config.xdg.configHome}/mozilla/firefox";
    };
  };
}
