{ config, pkgs, ... }:

{
  home-manager.users.sven = { pkgs, ... }: {
    home = {
      packages = with pkgs; [
        audacious # light music player
        gcompris # educational game suite for young children
        gimp # raster image editor
        klavaro # full-featured touch typing tutor
        krita # digital painting
        libreoffice # office suite for school work
        luanti # open-world Minecraft-style building game (formerly Minetest)
        supertux # Mario-style platformer with Tux
        supertuxkart # Tux kart racing
        tuxpaint # kid-friendly drawing
        tuxtype # touch typing tutor for kids
      ];
      sessionVariables = {
        MOZ_ENABLE_WAYLAND = 1;
      };
      stateVersion = "25.05"; /* The home.stateVersion option does not have a default and must be set */
    };

    programs = {
      bash = {
        enable = true;
      };
      command-not-found = {
        enable = true;
      };
      firefox = {
        enable = true;
      };
    };
  };
}
