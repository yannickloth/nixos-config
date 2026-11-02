{ config, pkgs, lib, ... }:

{
  imports = [
    ../common-hm.nix
    ../emacs-adult.nix
    ../opencode.nix
    ../../packages/orca/home.nix
    ../../packages/browseros/home.nix
    ../../packages/libreoffice-mcp/home.nix
    ../../packages/opencode-desktop/home.nix
    ../../packages/rea/home.nix
    ../../packages/herdr/home.nix
    # Unsloth Studio is deliberately NOT enabled for aeiuno (packages/
    # unsloth-studio/home.nix) — see the block after opencode.enable below.
    # ../../packages/unsloth-studio/home.nix
  ];

  # Enable the shared developer tools (neovim, vscode, direnv, etc.)
  commonHm.enableDeveloperTools = true;

  # Global opencode provider/model config (deepseek, Z.AI GLM Coding Plan
  # subscription, Kimi, Hetzner).
  opencode.enable = true;
  # CachyOS has no system agenix / /etc/secrets, so decrypt the shared provider
  # keys with aeiuno's user agenix key and materialize opencode's per-provider
  # key files from it; NixOS hosts keep the default /etc/secrets path (and must
  # not try to decrypt with the user key).
  opencode.envFile =
    lib.mkIf config.commonHm.isCachyOS config.age.secrets."opencode-keys.env".path;
  age = lib.mkIf config.commonHm.isCachyOS {
    identityPaths = [ "${config.home.homeDirectory}/.ssh/agenix_aeiuno" ];
    secrets."opencode-keys.env" = {
      file = ../../secrets/opencode-keys.env.age;
      mode = "0400";
    };
  };

  # BrowserOS neo: agent-driven browser for AI assistants (MCP).
  browseros.enable = true;

  # LibreOffice MCP extension (packages/libreoffice-mcp): MCP server inside the
  # open LibreOffice window on https://localhost:<port>/mcp.
  libreofficeMcp.enable = true;
  # 8766, not the 8765 default: nicky's LibreOffice owns 8765 on this host, and
  # a second instance on the same port adopts the other user's server instead of
  # starting its own (see the port option in packages/libreoffice-mcp/home.nix).
  libreofficeMcp.port = 8766;

  # opencode Desktop: the GUI of the opencode v2 line, next to the `opencode`
  # CLI in home.packages below.
  opencode-desktop.enable = true;

  # REA: reverse-engineering MCP server + CLI (packages/rea/home.nix).
  rea.enable = true;

  # herdr (packages/herdr/home.nix): terminal multiplexer / runtime for coding
  # agents, plus its agent skill and the integrations for the agents installed
  # here (opencode, pi, hermes).
  herdr.enable = true;

  # Orca (agent development environment): desktop client only. Runs locally per
  # user; pair it to a running `orca serve` (e.g. nicky's on laptop-p16) from
  # Settings only if you accept that its agents would run as THAT user.
  orca.enable = true;

  # Unsloth Studio (packages/unsloth-studio/home.nix) is deliberately NOT
  # enabled for aeiuno: it installs per-user into $HOME and binds :8888, so a
  # second instance on the same laptop would collide with nicky's (which runs
  # on every host, with linger) and double the multi-GB install. aeiuno's
  # opencode still reaches the same local System One endpoint at
  # 127.0.0.1:8888 as nicky's, so nothing is lost. On a host that is aeiuno's
  # alone, uncomment the import above and the enable below:
  # unsloth-studio.enable = true;

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
      opencode
      pi-coding-agent
      hermes-agent
      magpie
      deepseek-harness
      #jellyfin-media-player
      #joplin-desktop
      kdePackages.dolphin
      kdePackages.elisa
      kdePackages.filelight
      kdePackages.gwenview
      kdePackages.kalk
      kdePackages.kate
      kdePackages.okular
      (pkgs.callPackage ../../packages/masterpdfeditor { })
      # KDE mini-games: adults get them natively, kids via gated flatpak
      # (apps.flatpak.apps) — never both for the same user (see games/games.nix).
      kdePackages.granatier
      kdePackages.katomic
      kdePackages.kblocks
      kdePackages.kbreakout
      kdePackages.kdiamond
      kdePackages.kmahjongg
      kdePackages.kmines
      kdePackages.kpat
      kdePackages.kshisen
      kdePackages.ksudoku
      gnuplot # Command-line plotter for computed numbers (functions, data)
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
      maxima # Computer algebra system: integrate, solve, limit, sum, ODEs (CLI `maxima`)
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
      MOZ_ENABLE_WAYLAND = "1"; # for Firefox in Wayland sessions
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
    projects = "/home/aeiuno/sync/christine/Projects/";
    publicShare = "/home/aeiuno/sync/christine/Public/";
    templates = "/home/aeiuno/sync/christine/Templates/";
    videos = "/home/aeiuno/sync/christine/Videos/";
  };
}
