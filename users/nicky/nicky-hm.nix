{ config, pkgs, ... }:

{
  home-manager.users.nicky = { pkgs, ... }: {
    home = {
      packages = with pkgs; [
        amarok
        anki-bin
        (aspellWithDicts (dicts: with dicts; [ en en-computers en-science de fr nl wa])) # for emacs
        audacious
        audacious-plugins
        audacity
        bottles
        calibre
        xfce.catfish
        curlFull
        devbox
        drawio
        fdk_aac # A high-quality implementation of the AAC codec from Android
        fdk-aac-encoder # Command line encoder frontend for libfdk-aac encoder
        # (ffmpeg_5-full.overrideAttrs (old: rec {
        #   fdk_aac = pkgs.fdk_aac;
        #   fdkaacExtlib = true;
        #   gplLicensing = true;
        #   nonfreeLicensing = true;
        #   version3Licensing = true;
        # })
        #(pkgs.callPackage ./packages/development/ffmpeg/default.nix) # A complete, cross-platform solution to record, convert and stream audio and video
        freac
        freecad
        gnome.gnome-disk-utility
        #jetbrains-toolbox
        #jetbrains.clion
        jetbrains.datagrip
        #jetbrains.goland
        jetbrains.idea-ultimate
        jetbrains.rider
        flatpak
        fsearch
        gimp
        gnome.gnome-software
        hunspellDicts.fr-any
        hunspellDicts.en_US-large
        hunspellDicts.en_GB-large
        hunspellDicts.de_DE
        inkscape-with-extensions
        jellyfin-media-player
        #joplin-desktop
        kate
        keepassxc
        # keybase-gui
        kgraphviewer
        #kicad
        kid3-qt # A simple and powerful audio tag editor
        kodi
        krita
        libsForQt5.elisa
        libsForQt5.filelight
        libsForQt5.ksudoku # Sudoku for KDE
        lua
        mastodon
        meld # Visual diff and merge tool
        microsoft-edge
        obsidian # A powerful knowledge base that works on top of a local folder of plain text Markdown files
        pantheon.sideload
        plantuml
        podman-desktop
        powershell # Powerful cross-platform (Windows, Linux, and macOS) shell and scripting language based on .NET
        qalculate-qt
        recoll
        scrcpy
        scribus
        setzer # LaTeX editor written in Python with Gtk
        signal-desktop
        skypeforlinux
        speechd # speech-dispatcher, useful for Firefox
        stellarium # Desktop planetarium
        szyszka # A simple but powerful and fast bulk file renamer
        #teams-for-linux
        thunderbird
        tuner
        vivaldi
        vivaldi-ffmpeg-codecs
        vlc
        whatsapp-for-linux
        whitesur-gtk-theme
        xmind
        xplorer # A customizable, modern file manager
        zeal-qt6
        zoom-us
        zotero
      ];
      sessionVariables = {
        MOZ_ENABLE_WAYLAND = 1; # for Firefox in Wayland sessions
        NIXOS_OZONE_WL = "1"; # for Electron apps in Wayland sessions (VSCode, Chrome...)
      };
#       shellAliases = {
#         ls = "lsd"; # replace ls by lsd
#         ll = "ls -lha";
#       };
      stateVersion = "23.05"; /* The home.stateVersion option does not have a default and must be set */
    };
    
    programs = {
      bash = {
        enable = true;
      };
      chromium = {
        enable = true;
#         dictionaries = with pkgs; [
#           hunspellDicts.fr-any
#           hunspellDicts.en_US-large
#           hunspellDicts.en_GB-large
#           hunspellDicts.de_DE
#         ];
      };
      command-not-found = {
        enable = true;
      };
      direnv = {
        enable = true;
        enableBashIntegration = true; # see note on other shells below
        nix-direnv.enable = true;
      };
      #emacs =  with pkgs;{
      #  enable = false;
      #  package = emacs29-gtk3;
      #  extraConfig = (builtins.readFile ./emacs-config.el);
      #  extraPackages = epkgs: [
      #    epkgs.magit
      #    epkgs.markdown-mode
      #    epkgs.org-modern
      #    epkgs.org-roam
      #    epkgs.org-roam-bibtex
      #    epkgs.org-roam-timestamps
      #    epkgs.org-roam-ui
      #    epkgs.typescript-mode
      #  ];
      #};
      firefox = {
        enable = true;
        package = pkgs.firefox-bin;
      };
      git = {
        delta = {
          enable = true;
        };
        enable = true;
        extraConfig = {
        credential.helper = "${
          pkgs.git.override { withLibsecret = true; }
          }/bin/git-credential-libsecret";
        };
        lfs = {
          enable = true;
        };
        package = pkgs.gitFull;
        userName  = "Yannick Loth";
        userEmail = "727881+yannickloth@users.noreply.github.com";
      };
      gitui = {
        enable = true;
      };
      man.enable = true;
      neovim = {
        coc = { # code completion
          enable = true;
        };
        enable = true;
        plugins = with pkgs.vimPlugins; [
          vim-airline
          vim-nix
          {
            plugin = vim-startify;
            config = "let g:startify_change_to_vcs_root = 0";
          }
          yankring
        ];
        extraConfig = ''
          set mouse=a
        '';
        viAlias = true;
        vimAlias = true;
      };
      ssh = {
        enable = true;
      };
      starship = {
        enable = true;
        enableBashIntegration = true;
        enableZshIntegration = true;
      };
      vscode = {
        enable = true;
        enableExtensionUpdateCheck = true;
        enableUpdateCheck = true;
        mutableExtensionsDir = true;
        userSettings = {
        };
      };
    };


    services = {
      # kbfs.enable = true; # Keybase FS
      kdeconnect = {
        enable = true;
        indicator = true;
      };
      syncthing = {
        enable = true;
        tray = {
          enable = false;
        };
      };
      # keybase.enable = true;
    };
    xdg.userDirs = {
      createDirectories = false;
      enable = true;
      desktop = "/home/nicky/Tresors/yannick/LaptopSync/Desktop/";
      documents = "/home/nicky/Tresors/yannick/LaptopSync/Documents/";
      download = "/home/nicky/Tresors/yannick/LaptopSync/Downloads/";
      music = "/home/nicky/Tresors/yannick/LaptopSync/Music/";
      pictures = "/home/nicky/Tresors/yannick/LaptopSync/Pictures/";
      publicShare = "/home/nicky/Tresors/yannick/LaptopSync/Public/";
      templates = "/home/nicky/Tresors/yannick/LaptopSync/Templates/";
      videos = "/home/nicky/Tresors/yannick/LaptopSync/Videos/";
    };
  };
  # services.syncthing = {
  #   openDefaultPorts = true; # Whether to open the default ports in the firewall: TCP/UDP 22000 for transfers and UDP 21027 for discovery.
  # };
  networking.firewall= {
    allowedTCPPorts = [ 
      22000 # syncthing transfers
    ];
    allowedUDPPorts = [ 
      21027 # syncthing discovery
      22000 # syncthing transfers
    ];
  };
}
