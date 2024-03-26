{ config, lib, pkgs, ... }:

with lib;
{
  programs.gamemode = {
    enable = true; # Whether to enable GameMode to optimise system performance on demand.
    enableRenice = true; # Whether to enable CAP_SYS_NICE on gamemoded to support lowering process niceness.
    settings = {
      general = {
        renice = 10;
      };

      custom = {
        start = "${pkgs.libnotify}/bin/notify-send 'GameMode started'";
        end = "${pkgs.libnotify}/bin/notify-send 'GameMode ended'";
      };
    };
  };
  environment.systemPackages = with pkgs; [
    endless-sky
    gcompris
    gogdl # GOG Downloading module for Heroic Games Launcher
    #hedgewars # caution, is compiled for install
    heroic # A Native GOG, Epic, and Amazon Games Launcher for Linux, Windows and Mac
    #ioquake3
    libsForQt5.granatier
    libsForQt5.katomic
    libsForQt5.kblocks
    libsForQt5.kbreakout
    libsForQt5.kdiamond
    libsForQt5.kmahjongg
    libsForQt5.kmines
    libsForQt5.kpat
    libsForQt5.kshisen
    lutris
    quake3e
    #quake3hires
    #speed_dreams
    #vkquake
    xmoto
    zeroad
  ];
}
