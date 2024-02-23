{ config, pkgs, ... }:

{
  home-manager.users.aeiuno = { pkgs, ... }: {
    home = {
      packages = with pkgs; [
        amarok
        (aspellWithDicts (dicts: with dicts; [ en en-computers en-science de fr nl wa])) # for emacs
        audacious
        audacious-plugins
        audacity
        bottles
        calibre
        xfce.catfish
        curlFull
        drawio
        freac
        freecad
        gnome.gnome-disk-utility
        flatpak
        fsearch
        gimp-with-plugins
        gnome.gnome-software
        hunspellDicts.fr-any
        hunspellDicts.en_US-large
        hunspellDicts.en_GB-large
        hunspellDicts.de_DE
        inkscape-with-extensions
        jellyfin-media-player
        joplin-desktop
        kate
        keepassxc
        # keybase-gui
        kgraphviewer
        #kicad
        kodi
        krita
        libsForQt5.elisa
        libsForQt5.ksudoku # Sudoku for KDE
        microsoft-edge
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
        NIXOS_OZONE_WL = "1"; # for Electron apps in Wayland sessions (VSCode, Chrome...)
      };
      shellAliases = {
        ls = "lsd"; # replace ls by lsd
        ll = "ls -lha";
        l = "ls -l";
        la = "ls -a";
        lla = "ls -la";
        lt = "lsd --tree"; # --tree is not supported by 'ls', so in any case when ls is not aliased to lsd, 'lsd --tree' will continue to work
        ".." = "cd ..";
        nrs = "sudo nixos-rebuild switch";
        nrsu = "sudo nixos-rebuild switch --upgrade";
        myip = "curl ipinfo.io/ip"; # print public IPv4 address
      };
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
      direnv = {
        enable = true;
        enableBashIntegration = true; # see note on other shells below
        nix-direnv.enable = true;
      };
      emacs =  with pkgs;{
        enable = true;
        package = emacs29-gtk3;
        extraConfig = (builtins.readFile ../nicky/emacs-config.el);
        extraPackages = epkgs: [
          epkgs.magit
          epkgs.markdown-mode
          epkgs.org-modern
          epkgs.org-roam
          epkgs.org-roam-bibtex
          epkgs.org-roam-timestamps
          epkgs.org-roam-ui
          epkgs.typescript-mode
        ];
      };
      firefox = {
        enable = true;
        package = pkgs.firefox-bin;
      };
      git = {
        delta = {
          enable = true;
        };
        enable = true;
        lfs = {
          enable = true;
        };
        package = pkgs.gitFull;
        userName  = "aeiuno";
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
      # keybase.enable = true;
    };
    xdg.userDirs = {
      createDirectories = false;
      enable = true;
      desktop = "/home/aeiuno/Tresors/christine/LaptopSync/Desktop/";
      documents = "/home/aeiuno/Tresors/christine/LaptopSync/Documents/";
      download = "/home/aeiuno/Tresors/christine/LaptopSync/Downloads/";
      music = "/home/aeiuno/Tresors/christine/LaptopSync/Music/";
      pictures = "/home/aeiuno/Tresors/christine/LaptopSync/Pictures/";
      publicShare = "/home/aeiuno/Tresors/christine/LaptopSync/Public/";
      templates = "/home/aeiuno/Tresors/christine/LaptopSync/Templates/";
      videos = "/home/aeiuno/Tresors/christine/LaptopSync/Videos/";
    };
  };

}
