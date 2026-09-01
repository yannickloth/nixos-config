{ config, pkgs, ... }:

{
  imports = [
    ../common-hm.nix
    ../emacs-adult.nix
  ];

  # Enable the shared developer tools (neovim, vscode, direnv, etc.)
  commonHm.enableDeveloperTools = true;

  home = {
    username = "aeiuno";
    homeDirectory = "/home/aeiuno";
    packages = with pkgs; [
      charis # SIL Charis, a serif font recommended for readability
      stix-two # STIX Two, a Unicode font covering scientific and mathematical notation
      amarok
      anki-bin
      (aspellWithDicts (dicts: with dicts; [ en en-computers en-science de fr nl wa ])) # for emacs
      audacious
      audacious-plugins
      audacity
      bottles
      calibre
      catfish
      cobang # QR code scanner desktop app for Linux
      curlFull
      digikam # photo management / organizer
      # drawio
      freac
      #freecad # commented out because compilation takes too much time, just install it with flatpak
      gnome-disk-utility
      flatpak
      fsearch
      gimp
      gnome-software
      gparted
      hunspellDicts.fr-any
      hunspellDicts.en_US-large
      hunspellDicts.en_GB-large
      hunspellDicts.de_DE
      inkscape-with-extensions
      jetbrains-toolbox # JetBrains IDEs (IntelliJ, PyCharm, ...) via Toolbox
      #jellyfin-media-player
      #joplin-desktop
      kdePackages.dolphin
      kdePackages.elisa
      kdePackages.filelight
      kdePackages.gwenview
      kdePackages.kalk
      kdePackages.kate
      kdePackages.okular
      keepassxc
      # keybase-gui
      # kgraphviewer
      #kicad
      kid3-qt # A simple and powerful audio tag editor
      kodi
      krita
      libreoffice
      #microsoft-edge
      lutris
      mousai # Identify any songs in seconds
      obsidian # A powerful knowledge base that works on top of a local folder of plain text Markdown files
      pantheon.sideload
      #podman-desktop
      qalculate-qt
      recoll
      signal-desktop
      speechd # speech-dispatcher, useful for Firefox
      # stellarium # Desktop planetariums
      thunderbird
      tuner
      vlc # native media player (parents only; kids use the gated flatpak)
      libmicrodns # for playing from VLC onto ChromeCast
      protobuf # for playing from VLC onto ChromeCast
      #vivaldi
      #vivaldi-ffmpeg-codecs
      zotero
    ];
    sessionVariables = {
      MOZ_ENABLE_WAYLAND = 1; # for Firefox in Wayland sessions
      # NIXOS_OZONE_WL = "1"; # for Electron apps in Wayland sessions (VSCode, Chrome...) # disabled because VSCode/Electron/Chromium does nothing with it (unknown option), except issue a warning about it being unknown.
    };
    /*shellAliases = {
      ls = "lsd"; # replace ls by lsd
      ll = "ls -lha";
    };*/
  };

  programs = {
    delta = {
      enable = true; # Whether to enable the delta syntax highlighter.
      enableGitIntegration = true;
    };
    git = {
      enable = true;
      # extraConfig = {
      #   credential.helper = "${pkgs.git.override { withLibsecret = true; }}/bin/git-credential-libsecret";
      #};
      lfs = {
        enable = true; # Whether to enable Git Large File Storage.
      };
      #package = pkgs.gitFull;
      settings = {
        user.name = "aeiuno";
        user.email = "727881+yannickloth@users.noreply.github.com";
      };
    };
  };

  # Keybase not enabled: kbfs.enable and keybase.enable are intentionally left off.

  xdg.configFile."user-dirs.dirs".force = true;

  xdg.userDirs = {
    createDirectories = false;
    enable = true;
    setSessionVariables = true; # keep legacy default
    desktop = "/home/aeiuno/sync/christine/Desktop/";
    documents = "/home/aeiuno/sync/christine/Documents/";
    download = "/home/aeiuno/sync/christine/Downloads/";
    music = "/home/aeiuno/sync/christine/Music/";
    pictures = "/home/aeiuno/sync/christine/Pictures/";
    publicShare = "/home/aeiuno/sync/christine/Public/";
    templates = "/home/aeiuno/sync/christine/Templates/";
    videos = "/home/aeiuno/sync/christine/Videos/";
  };
}
