{ config, lib, pkgs, ... }:

with lib;
{
  hardware = {
    openrazer = {
      enable = true; # Whether to enable OpenRazer drivers and userspace daemon .
      users = [ "aeiuno" "nicky" ]; # Usernames to be added to the “openrazer” group, so that they can start and interact with the OpenRazer userspace daemon.
    };
    # opentabletdriver.enable = true;
    # wooting.enable = true; # Whether to enable support for Wooting keyboards. Note that users must be in the “input” group for udev rules to apply.
    #xone.enable = true; # Whether to enable the xone driver for Xbox One and Xbox Series X|S accessories.
    #xpadneo.enable = true; # Whether to enable the xpadneo driver for Xbox One wireless controllers.
  };
  
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
  services = {
    hardware.openrgb = {
      enable = true; # Whether to enable OpenRGB server, for RGB lighting control.
    };
    input-remapper = {
      enable = true; # Whether to enable input-remapper, an easy to use tool to change the mapping of your input device buttons.
      # enableUdevRules = false; # Whether to enable udev rules added by input-remapper to handle hotplugged devices. Currently disabled by default due to https://github.com/sezanzeb/input-remapper/issues/140.
    };
    joycond.enable = true; # Whether to enable support for Nintendo Pro Controllers and Joycons.
    switcherooControl.enable = true; # Whether to enable switcheroo-control, a D-Bus service to check the availability of dual-GPU.
    system76-scheduler.enable = true;
  };
  environment.systemPackages = with pkgs; [
    boxbuddy # An unofficial GUI for managing your Distroboxes, written with GTK4 + Libadwaita
    displaylink # Synaptics DisplayLink DL-5xxx, DL-41xx and DL-3x00 Driver for Linux. https://www.synaptics.com/products/displaylink-graphics
    distrobox # Wrapper around podman or docker to create and start containers
    duperemove # A simple tool for finding duplicated extents and submitting them for deduplication
    endless-sky
    gcompris
    gogdl # GOG Downloading module for Heroic Games Launcher
    # handheld-daemon # Linux support for handheld gaming devices like the Legion Go, ROG Ally, and GPD Win
    #hedgewars # caution, is compiled for install
    heroic # A Native GOG, Epic, and Amazon Games Launcher for Linux, Windows and Mac
    #ioquake3
    libcec # Allows you (with the right hardware) to control your device with your TV remote control using existing HDMI cabling
    libcec_platform # Platform library for libcec and Kodi addons
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
    mangohud # A Vulkan and OpenGL overlay for monitoring FPS, temperatures, CPU/GPU load and more
    obs-studio-plugins.obs-vkcapture # OBS Linux Vulkan/OpenGL game capture
    protonup-qt # Install and manage Proton-GE and Luxtorpeda for Steam and Wine-GE for Lutris with this graphical user interface.
    ptyxis # A terminal for GNOME with first-class support for containers
    quake3e
    #quake3hires
    #speed_dreams
    vkbasalt # A Vulkan post processing layer for Linux
    vkbasalt-cli # Command-line utility for vkBasalt
    #vkquake
    # linux-wallpaperengine # Wallpaper Engine backgrounds for Linux # depends on freeimage, which is insecure according to nix/nixpkgs
    xmoto
    xwaylandvideobridge # Utility to allow streaming Wayland windows to X applications
    zeroad
  ];
}
