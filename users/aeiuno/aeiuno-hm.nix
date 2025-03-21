{ config, pkgs, ... }:

{
  home-manager.users.aeiuno = { pkgs, ... }: {
    home = {
      packages = with pkgs; [
        amarok
        anki-bin
        (aspellWithDicts (dicts: with dicts; [ en en-computers en-science de fr nl wa ])) # for emacs
        audacious
        audacious-plugins
        audacity
        bottles
        calibre
        xfce.catfish
        cobang # QR code scanner desktop app for Linux
        curlFull
        digikam
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
        jellyfin-media-player
        #joplin-desktop
        kdePackages.kate
        keepassxc
        # keybase-gui
        kgraphviewer
        #kicad
        kid3-qt # A simple and powerful audio tag editor
        kodi
        krita
        libsForQt5.elisa
        libsForQt5.filelight
        #microsoft-edge
        mousai # Identify any songs in seconds
        obsidian # A powerful knowledge base that works on top of a local folder of plain text Markdown files
        pantheon.sideload
        #podman-desktop
        qalculate-qt
        recoll
        signal-desktop
        skypeforlinux
        speechd # speech-dispatcher, useful for Firefox
        stellarium # Desktop planetariums
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
      stateVersion = "23.05"; /* The home.stateVersion option does not have a default and must be set */
    };

    programs = {
      bash = {
        enable = true;
      };
      chromium = {
        enable = true;
        #enablePlasmaBrowserIntegration = true;
        #         dictionaries = with pkgs; [
        #           hunspellDicts.fr-any
        #           hunspellDicts.en_US-large
        #           hunspellDicts.en_GB-large
        #           hunspellDicts.de_DE
        #         ];
        commandLineArgs = [
          "--enable-features=VaapiVideoDecodeLinuxGL"
          "--ignore-gpu-blocklist"
          "--enable-zero-copy"
        ];
      };
      command-not-found = {
        enable = true;
      };
      direnv = {
        enable = true;
        enableBashIntegration = true; # see note on other shells below
        nix-direnv.enable = true;
      };
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
      git = {
        delta = {
          enable = true; # Whether to enable the delta syntax highlighter.
        };
        enable = true;
        extraConfig = {
          credential.helper = "${pkgs.git.override { withLibsecret = true; }}/bin/git-credential-libsecret";
        };
        lfs = {
          enable = true; # Whether to enable Git Large File Storage.
        };
        #package = pkgs.gitFull;
        userName = "aeiuno";
        userEmail = "727881+yannickloth@users.noreply.github.com";
      };
      gitui = {
        enable = true;
      };
      man.enable = true;
      neovim = {
        coc = {
          # code completion
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
        mutableExtensionsDir = true;
        profiles = {
          default = {
            enableExtensionUpdateCheck = true;
            enableUpdateCheck = true;
            userSettings = { };
          };
        };
      };
    };

    services = {
      # kbfs.enable = true; # Keybase FS
      kdeconnect = {
        enable = true;
        indicator = true;
      };
      # keybase.enable = true;
      syncthing = {
        enable = true;
        tray = {
          enable = false;
        };
      };
    };
    xdg.userDirs = {
      createDirectories = false;
      enable = true;
      desktop = "/home/aeiuno/syncthing/christine/LaptopSync/Desktop/";
      documents = "/home/aeiuno/syncthing/christine/LaptopSync/Documents/";
      download = "/home/aeiuno/syncthing/christine/LaptopSync/Downloads/";
      music = "/home/aeiuno/syncthing/christine/LaptopSync/Music/";
      pictures = "/home/aeiuno/syncthing/christine/LaptopSync/Pictures/";
      publicShare = "/home/aeiuno/syncthing/christine/LaptopSync/Public/";
      templates = "/home/aeiuno/syncthing/christine/LaptopSync/Templates/";
      videos = "/home/aeiuno/syncthing/christine/LaptopSync/Videos/";
    };
  };
  networking.firewall = {
    allowedTCPPorts = [
      22000 # syncthing transfers
    ];
    allowedUDPPorts = [
      21027 # syncthing discovery
      22000 # syncthing transfers
    ];
  };
}
