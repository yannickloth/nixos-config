{ config, pkgs, ... }:

{
  imports = [
    ../common-hm.nix
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
      #digikam
      # drawio
      freac
      #freecad # commented out because compilation takes too much time, just install it with flatpak
      gnome-disk-utility
      flatpak
      fsearch
      gimp
      gnome-software
      hunspellDicts.fr-any
      hunspellDicts.en_US-large
      hunspellDicts.en_GB-large
      hunspellDicts.de_DE
      inkscape-with-extensions
      jetbrains-toolbox # JetBrains IDEs (IntelliJ, PyCharm, ...) via Toolbox
      #jellyfin-media-player
      #joplin-desktop
      kdePackages.kate
      keepassxc
      # keybase-gui
      # kgraphviewer
      #kicad
      kid3-qt # A simple and powerful audio tag editor
      kodi
      krita
      kdePackages.elisa
      kdePackages.filelight
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
      #vivaldi
      #vivaldi-ffmpeg-codecs
      vlc
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
    #       emacs =  with pkgs;{
    #         enable = true;
    #         package = emacs29-gtk3;
    #         extraConfig = (builtins.readFile ../nicky/emacs-config.el);
    #         extraPackages = epkgs: [
    #           epkgs.magit
    #           epkgs.markdown-mode
    #           epkgs.org-modern
    #           epkgs.org-roam
    #           epkgs.org-roam-bibtex
    #           epkgs.org-roam-timestamps
    #           epkgs.org-roam-ui
    #           epkgs.typescript-mode
    #         ];
    #       };
    # firefox = {
    #   enable = true;
    #   #nativeMessagingHosts=[euwebid ];
    #   package = pkgs.firefox-bin;
    # };
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

  xdg.userDirs = {
    createDirectories = false;
    enable = true;
    setSessionVariables = true; # keep legacy default
    desktop = "/home/aeiuno/syncthing/christine/LaptopSync/Desktop/";
    documents = "/home/aeiuno/syncthing/christine/LaptopSync/Documents/";
    download = "/home/aeiuno/syncthing/christine/LaptopSync/Downloads/";
    music = "/home/aeiuno/syncthing/christine/LaptopSync/Music/";
    pictures = "/home/aeiuno/syncthing/christine/LaptopSync/Pictures/";
    publicShare = "/home/aeiuno/syncthing/christine/LaptopSync/Public/";
    templates = "/home/aeiuno/syncthing/christine/LaptopSync/Templates/";
    videos = "/home/aeiuno/syncthing/christine/LaptopSync/Videos/";
  };
}
