{ config, pkgs, ... }:

{
  imports = [
    ../common-hm.nix
  ];

  home = {
    username = "sven";
    homeDirectory = "/home/sven";
    packages = with pkgs; [
      audacious # light music player
      extremetuxracer # high-speed arctic penguin racing game
      gcompris # educational game suite for young children
      gimp # raster image editor
      klavaro # full-featured touch typing tutor
      kdePackages.ktuberling # fun "potato head" constructor game for young kids
      krita # digital painting
      libreoffice # office suite for school work
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

  programs = {
    firefox = {
      enable = true;
      configPath = "${config.xdg.configHome}/mozilla/firefox";
    };
  };
}
