{ config, lib, pkgs, ... }:

with lib;
{
  hardware = {
    openrazer = {
      enable = false; # Whether to enable OpenRazer drivers and userspace daemon .
      users = [ "aeiuno" "nicky" ]; # Usernames to be added to the “openrazer” group, so that they can start and interact with the OpenRazer userspace daemon.
    };
    # opentabletdriver.enable = true;
    # wooting.enable = true; # Whether to enable support for Wooting keyboards. Note that users must be in the “input” group for udev rules to apply.
    #xone.enable = true; # Whether to enable the xone driver for Xbox One and Xbox Series X|S accessories.
    #xpadneo.enable = true; # Whether to enable the xpadneo driver for Xbox One wireless controllers.
  };
  
  programs.gamemode = { # https://wiki.nixos.org/wiki/GameMode
    enable = true; # Whether to enable GameMode to optimise system performance on demand.
    enableRenice = true; # Whether to enable CAP_SYS_NICE on gamemoded to support lowering process niceness.
    settings = {
      general = {
        renice = 1; # Unlike renicing a process with the renice command, GameMode uses a positive value and negates it before applying it to the process.
      };

      custom = {
        start = "${pkgs.libnotify}/bin/notify-send 'GameMode started'";
        end = "${pkgs.libnotify}/bin/notify-send 'GameMode ended'";
      };
    };
  };
  services = {
    hardware.openrgb = {
      enable = false; # Whether to enable OpenRGB server, for RGB lighting control.
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
    # displaylink # Synaptics DisplayLink DL-5xxx, DL-41xx and DL-3x00 Driver for Linux. https://www.synaptics.com/products/displaylink-graphics
    distrobox # Wrapper around podman or docker to create and start containers
    duperemove # A simple tool for finding duplicated extents and submitting them for deduplication
    endless-sky
    gamemode # Optimise Linux system performance on demand. CLI app.
    gamescope # Fullscreen compositor that wraps games (Lutris/Steam use it for
              # exclusive fullscreen); Lutris's system check looks it up in PATH.
    gogdl # GOG Downloading module for Heroic Games Launcher
    # handheld-daemon # Linux support for handheld gaming devices like the Legion Go, ROG Ally, and GPD Win
    #hedgewars # caution, is compiled for install
    heroic # A Native GOG, Epic, and Amazon Games Launcher for Linux, Windows and Mac
    #ioquake3
    libcec # Allows you (with the right hardware) to control your device with your TV remote control using existing HDMI cabling
    libcec_platform # Platform library for libcec and Kodi addons
    # KDE mini-games are NOT installed system-wide: adults get them via
    # home-manager (users/*/nicky-hm.nix, aeiuno-hm.nix), kids via flatpak
    # (apps.flatpak.apps) so malcontent gates them. A native copy visible to
    # the kids alongside their flatpak copy showed up as a duplicate.
    # kdePackages.granatier
    # kdePackages.katomic
    # kdePackages.kblocks
    # kdePackages.kbreakout
    # kdePackages.kdiamond
    # kdePackages.kmahjongg
    # kdePackages.kmines
    # kdePackages.kpat
    # kdePackages.kshisen
    # kdePackages.ksudoku
    # lutris
    mangohud # A Vulkan and OpenGL overlay for monitoring FPS, temperatures, CPU/GPU load and more
    obs-studio-plugins.obs-vkcapture # OBS Linux Vulkan/OpenGL game capture
    # Free, open source launcher for Minecraft. System-wide on NixOS, so every
    # user on the host gets it; the standalone CachyOS deployment installs the
    # same package per-user (users/common-hm.nix). The shared setup (extra
    # binaries for mods, controller and GameMode support, Java runtimes) lives
    # in packages/prismlauncher.
    (callPackage ../packages/prismlauncher { })
    protonup-qt # Install and manage Proton-GE and Luxtorpeda for Steam and Wine-GE for Lutris with this graphical user interface.
    ptyxis # A terminal for GNOME with first-class support for containers
    quake3e
    # RetroArch with the retro cores bundled AND a declarative baseline
    # configuration. retroarch-bare.wrapper writes `settings` into a
    # read-only retroarch.cfg in the nix store and wraps the binary with
    # --appendconfig=<that file>.
    #
    # PRECEDENCE (verified in the v1.22.2 source, config_file.c): the config
    # hashmap keeps the FIRST occurrence of each key, so for any key it
    # contains, a user's ~/.config/retroarch/retroarch.cfg wins over this
    # append config. RetroArch rewrites the user's cfg on every exit with ALL
    # effective settings (config_save_file), so after the first run each
    # user's cfg is self-sustaining and this append config only acts as the
    # first-launch seed for users without a cfg yet. (games/retroarch-hm.nix
    # additionally re-points the writable dirs in existing user cfgs once.)
    # The per-user RetroAchievements login token lives only in the user's
    # cfg, which RA never deletes, so it survives every launch and rebuild.
    #
    # `~` in path values is expanded to each user's $HOME at load time
    # (config_get_path -> fill_pathname_expand_special), and abbreviated back
    # on save — that is how the per-user dirs below work from one shared
    # system-wide config.
    #
    # The wrapper also adds -L <cores dir>: RetroArch v1.22.2 treats a
    # directory argument to -L as its libretro search directory (it sets
    # libretro_directory), so `retroarch file.gba` auto-picks the right core
    # by extension. retroarch-bare's wrapper passthru
    # (pkgs/by-name/re/retroarch-bare/package.nix) merges three read-only
    # store-path resource dirs (assets, joypad autoconfig, core info) into
    # the settings below; only joypad_autoconfig_dir is overridden here, to
    # the per-user home dir, because "Save Controller Configuration" writes
    # to it (config_save_autoconf_profile) and a read-only store path breaks
    # saving.
    #
    # All core names below verified against the libretro scope
    # (pkgs/applications/emulators/libretro/default.nix) of the pinned
    # nixpkgs rev in flake.lock.
    (retroarch-bare.wrapper {
      cores = with libretro; [
        mesen             # NES (also SNES/GB/GBC accuracy pick)
        snes9x            # SNES
        bsnes             # SNES cycle-accurate
        genesis-plus-gx   # SEGA Mega Drive / Genesis, Master System, Game Gear
        mgba              # Game Boy, Game Boy Color, Game Boy Advance
        mupen64plus       # Nintendo 64
        beetle-pce-fast   # PC Engine / TurboGrafx-16 (mednafen fast core)
        beetle-wswan      # WonderSwan / WonderSwan Color
        beetle-ngp        # Neo Geo Pocket / Color
        beetle-vb         # Virtual Boy
        beetle-lynx       # Atari Lynx
        virtualjaguar     # Atari Jaguar
      ];
      # Family baseline: first-launch seed (fresh users). RA writes the
      # effective values into the user's retroarch.cfg on first exit, from
      # where they persist (RA round-trips every key).
      settings = {
        # --- Low latency ---
        run_ahead = "true";
        run_ahead_frames = "1";
        run_ahead_hide_warnings = "true";
        frame_delay = "0"; # 0 = auto; tune 0-3 if a core drops frames
        # --- RetroAchievements (retroachievements.org) ---
        cheevos_enable = "true";
        cheevos_hardcore_mode_enable = "true";
        # --- Directories ---
        # System/BIOS files of the shared family ROM library. (On a host
        # where /sync is absent the path simply goes unused.)
        system_directory = "/sync/90-99 - Public stuff/roms/BIOS";
        # Controller profiles: per-user home dir, NOT the read-only store
        # default from the wrapper passthru. Profile files load from here
        # (and the driver-specific subdir if present), and "Save Controller
        # Configuration" writes here. games/retroarch-hm.nix seeds the
        # family Xbox 360 profile into it.
        joypad_autoconfig_dir = "~/.config/retroarch/autoconfig";
      };
    })
    #quake3hires
    #speed_dreams
    vkbasalt # A Vulkan post processing layer for Linux
    vkbasalt-cli # Command-line utility for vkBasalt
    #vkquake
    # linux-wallpaperengine # Wallpaper Engine backgrounds for Linux # depends on freeimage, which is insecure according to nix/nixpkgs
    xmoto
    #zeroad
  ];
}
