# Symlink this file into ~/.config/home-manager/ : 
# ln -sf ~/code/nixos-config/users/nicky/home.nix ~/.config/home-manager/home.nix
#
# OR skip the symlink: home-manager switch -f ~/code/nixos-config/users/nicky/home.nix
#
{
  config,
  pkgs,
  lib,
  ...
}:

let
  # Tresorit FHS environment definition
  tresoritFHS = pkgs.buildFHSEnv {
    name = "tresorit-fhs";
    targetPkgs = pkgs: with pkgs; [
      qt5.qtbase
      libsForQt5.qtscript
      libsForQt5.qtx11extras
      libsForQt5.qtdeclarative
      libsForQt5.qtsvg
      libsForQt5.qtgraphicaleffects
      libsForQt5.qtquickcontrols2
      libsForQt5.qtwayland
      fuse
      libxcb
      libx11
      glibc
      libgcc
      pcre2
      libcap
      libxcb-wm
      libxcb-image
      libxcb-keysyms
      libxcb-render-util
      libxkbcommon
      libxext
      xcb-util-cursor
      xcbutilxrm
      libGLU
      libGL
      krb5
    ];
    runScript = "bash";
    meta = with pkgs.lib; {
      description = "FHS environment for Tresorit";
    };
  };
  secrets = if builtins.pathExists ./secrets.nix
            then import ./secrets.nix
            else {};
in
{
  nixpkgs.config.allowUnfree = true; # This allows you to install unfree software, such as Google Chrome, Steam or MasterPDFEditor.

  # Home Manager needs a bit of information about you and the paths it should
  # manage.
  home.username = "nicky";
  home.homeDirectory = "/home/nicky";

  # This value determines the Home Manager release that your configuration is
  # compatible with. This helps avoid breakage when a new Home Manager release
  # introduces backwards incompatible changes.
  #
  # You should not change this value, even if you update Home Manager. If you do
  # want to update the value, then make sure to first check the Home Manager
  # release notes.
  home.stateVersion = "25.05"; # Please read the comment before changing.

  # The home.packages option allows you to install Nix packages into your
  # environment.
  home.packages = with pkgs; [
    # # Adds the 'hello' command to your environment. It prints a friendly
    # # "Hello, world!" when run.
    # pkgs.hello

    charis # SIL Charis, a serif font recommended for readability
    stix-two # STIX Two, a Unicode font covering scientific and mathematical notation

    # # It is sometimes useful to fine-tune packages, for example, by applying
    # # overrides. You can do that directly here, just don't forget the
    # # parentheses. Maybe you want to install Nerd Fonts with a limited number of
    # # fonts?
    # (pkgs.nerdfonts.override { fonts = [ "FantasqueSansMono" ]; })

    # # You can also create simple shell scripts directly inside your
    # # configuration. For example, this adds a command 'my-hello' to your
    # # environment:
    # (pkgs.writeShellScriptBin "my-hello" ''
    #   echo "Hello, ${config.home.username}!"
    # '')

    bun
    bat
    fd
    jq
    lsd
    netcat
    nil # Nix Language Server
    ripgrep
    tree # Command to produce a depth indented directory listing
    typst # New markup-based typesetting system that is powerful and easy to learn
    typstyle # Format your typst source code
    yq
    yed

    git-lfs
    gh

    (masterpdfeditor.overrideAttrs (old: rec {
      pname = "masterpdfeditor";
      version = "5.8.70";
      src = fetchurl {
        url = "https://code-industry.net/public/master-pdf-editor-${version}-qt5.x86_64.tar.gz";
        sha256 = "sha256-mheHvHU7Z1jUxFWEEfXv2kVO51t/edTK3xV82iteUXM=";
      };
      # Disable fixup phase to avoid build errors with custom binary location
      dontFixup = true;
      # Disable Qt wrapper to manually control Qt environment variables
      dontWrapQtApps = true;
      nativeBuildInputs = [ pkgs.makeWrapper ];
      # I don't know why the installPhase must be overridden, but without it, the script does not find license_en.txt (which it shouldn't even try to use...) and fails.
      installPhase = ''
        runHook preInstall

        p=$out/opt/masterpdfeditor
        mkdir -p $out/bin

        substituteInPlace masterpdfeditor5.desktop \
          --replace 'Exec=/opt/master-pdf-editor-5' "Exec=$out/bin" \
          --replace 'Path=/opt/master-pdf-editor-5' "Path=$out/bin" \
          --replace 'Icon=/opt/master-pdf-editor-5' "Icon=$out/share/pixmaps"

        install -Dm644 -t $out/share/pixmaps      masterpdfeditor5.png
        echo -e '\nStartupWMClass=net.code-industry.masterpdfeditor5' >> masterpdfeditor5.desktop
        install -Dm644 -t $out/share/applications masterpdfeditor5.desktop
        install -Dm755 -t $p                      masterpdfeditor5
        install -Dm644 license.txt $out/share/licenses/$pname/LICENSE
        ln -s $p/masterpdfeditor5 $out/bin/masterpdfeditor5
        cp -v -r stamps templates lang fonts $p

        runHook postInstall

        # Create a wrapper script that sets Qt environment variables to fix popup rendering issues
        mv $out/bin/masterpdfeditor5 $out/bin/.masterpdfeditor5-unwrapped
        makeWrapper $out/bin/.masterpdfeditor5-unwrapped $out/bin/masterpdfeditor5 \
          --set QT_QPA_PLATFORM xcb \
          --set QT_XCB_GL_INTEGRATION none \
          --prefix LD_LIBRARY_PATH : ${
            pkgs.lib.makeLibraryPath [
              pkgs.libx11
              pkgs.libxrandr
              pkgs.libGL
            ]
          }
        # QT_QPA_PLATFORM=xcb: Force Qt to use X11/XCB backend
        # QT_XCB_GL_INTEGRATION=none: Disable OpenGL integration to prevent rendering issues  
        # LD_LIBRARY_PATH: Add required X11 and OpenGL libraries
      '';
    }))
    obsidian

    nodejs
    languagetool

    jdk25 # Java 25
    elan # Lean theorem prover version manager

    rclone # Used to mount nestor shares
    # fuse3 # Already installed as a CachyOS package.

    quarto
    # panache

    jbang

    # Merged from the previous nicky-hm.nix config
    amarok
    anki-bin
    (aspellWithDicts (dicts: with dicts; [ en en-computers en-science de fr nl wa ])) # for emacs
    audacious
    audacious-plugins
    audacity
    bottles
    calibre
    cobang # QR code scanner desktop app for Linux
    conda # Conda is a package manager for Python
    curlFull
    devbox
    fdk_aac # A high-quality implementation of the AAC codec from Android
    fdk-aac-encoder # Command line encoder frontend for libfdk-aac encoder
    flatpak
    freac
    fsearch
    gimp
    gnome-disk-utility
    gnome-software
    hunspellDicts.fr-any
    hunspellDicts.en_US-large
    hunspellDicts.en_GB-large
    hunspellDicts.de_DE
    inkscape-with-extensions
    jetbrains-toolbox
    kdePackages.elisa
    kdePackages.filelight
    kdePackages.kate
    keepassxc
    kid3-qt # A simple and powerful audio tag editor
    kodi
    krita
    lua
    mastodon
    meld # Visual diff and merge tool
    mousai # Identify any songs in seconds
    musescore
    pantheon.sideload
    pdfstudioviewer # Easy to use, full-featured PDF viewing software.
    plantuml
    podman-desktop
    powershell # Powerful cross-platform (Windows, Linux, and macOS) shell and scripting language based on .NET
    qalculate-qt
    recoll
    scrcpy
    scribus
    signal-desktop
    speechd # speech-dispatcher, useful for Firefox
    szyszka # A simple but powerful and fast bulk file renamer
    thunderbird
    tinymist # Integrated language service for Typst
    tuner
    vlc
    whitesur-gtk-theme
    catfish
    zeal # Simple offline API documentation browser.
    zoom-us
    zotero

    tresoritFHS
  ];
  home.file.".npmrc".text = ''
    prefix=${config.home.homeDirectory}/.npm-global
  '';

  # Add local bin (Claude Code native), npm global bin, elan, and opencode to PATH
  home.sessionPath = [
    "$HOME/.local/bin"
    "$HOME/.elan/bin"
    "$HOME/.npm-global/bin"
    "$HOME/.opencode/bin"
  ];

  home.activation.installClaudeTools = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    # Install Claude Code native binary (auto-updates itself)
    if [ ! -f "$HOME/.local/bin/claude" ]; then
      $DRY_RUN_CMD ${pkgs.curl}/bin/curl -fsSL https://claude.ai/install.sh | $DRY_RUN_CMD bash
    fi

    # Install OpenCode (auto-updates itself)
    if [ ! -f "$HOME/.opencode/bin/opencode" ]; then
      $DRY_RUN_CMD ${pkgs.curl}/bin/curl -fsSL https://opencode.ai/install | $DRY_RUN_CMD bash
    fi

    # Install claude-trace via npm
    export NPM_CONFIG_PREFIX="$HOME/.npm-global"
    $DRY_RUN_CMD ${pkgs.nodejs}/bin/npm install -g @mariozechner/claude-trace@latest

    # Install Cline to use Cline Kanban
    $DRY_RUN_CMD ${pkgs.nodejs}/bin/npm install -g cline

    # Install pi (original AI coding agent) via npm
    export NPM_CONFIG_PREFIX="$HOME/.npm-global"
    if ! command -v pi &>/dev/null; then
      $DRY_RUN_CMD ${pkgs.nodejs}/bin/npm install -g --ignore-scripts @earendil-works/pi-coding-agent@latest
    fi

    # Install oh-my-pi (omp — fork/successor) via npm
    export NPM_CONFIG_PREFIX="$HOME/.npm-global"
    if ! command -v omp &>/dev/null; then
      $DRY_RUN_CMD ${pkgs.nodejs}/bin/npm install -g --ignore-scripts @oh-my-pi/pi-coding-agent@latest
    fi

    # Install omp-deck (web cockpit for omp) via npm
    export NPM_CONFIG_PREFIX="$HOME/.npm-global"
    if ! command -v omp-deck &>/dev/null; then
      $DRY_RUN_CMD ${pkgs.nodejs}/bin/npm install -g omp-deck@latest
    fi
  '';

  home.activation.setupTresorit = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    # Install Tresorit if not already installed
    if [ ! -f "$HOME/.local/share/tresorit/tresorit" ]; then
      echo "Installing Tresorit..."
      $DRY_RUN_CMD ${pkgs.curl}/bin/curl -fL -o /tmp/tresorit_installer.run https://installer.tresorit.com/tresorit_installer.run
      $DRY_RUN_CMD chmod +x /tmp/tresorit_installer.run
      $DRY_RUN_CMD /tmp/tresorit_installer.run --target "$HOME/.local/share/tresorit" --noexec
      $DRY_RUN_CMD rm /tmp/tresorit_installer.run
    fi

    # Create desktop file in applications directory
    DESKTOP_FILE="$HOME/.local/share/applications/tresorit-fhs.desktop"
    $DRY_RUN_CMD mkdir -p "$(dirname "$DESKTOP_FILE")"
    if [ -f "$DESKTOP_FILE" ]; then
      $DRY_RUN_CMD rm -f "$DESKTOP_FILE"
    fi
    $DRY_RUN_CMD cat > "$DESKTOP_FILE" <<EOF
[Desktop Entry]
Version=1.0
Type=Application
Name=Tresorit FHS
Comment=Secure cloud storage
Exec=${config.home.homeDirectory}/.local/share/tresorit/tresorit_fhs_launcher.sh
Icon=tresorit
Terminal=false
Categories=Network;
EOF

    # Disable Tresorit's broken autostart config
    if [ -f "$HOME/.config/autostart/tresorit.desktop" ]; then
      $DRY_RUN_CMD mv "$HOME/.config/autostart/tresorit.desktop" "$HOME/.config/autostart/tresorit.desktop.bk"
      $DRY_RUN_CMD sed -i 's/^/# /' "$HOME/.config/autostart/tresorit.desktop.bk"
    fi

    # Set up autostart for FHS version
    AUTOSTART_FILE="$HOME/.config/autostart/tresorit-fhs.desktop"
    $DRY_RUN_CMD mkdir -p "$(dirname "$AUTOSTART_FILE")"
    if [ -f "$AUTOSTART_FILE" ]; then
      $DRY_RUN_CMD rm -f "$AUTOSTART_FILE"
    fi
    $DRY_RUN_CMD cat > "$AUTOSTART_FILE" <<EOF
[Desktop Entry]
Version=1.0
Type=Application
Name=Tresorit FHS
Comment=Secure cloud storage
Exec=${config.home.homeDirectory}/.local/share/tresorit/tresorit_fhs_launcher.sh
Icon=tresorit
Terminal=false
Categories=Network;
EOF
  '';

  # Home Manager is pretty good at managing dotfiles. The primary way to manage
  # plain files is through 'home.file'.
  home.file = {
    # Tresorit FHS launcher script
    ".local/share/tresorit/tresorit_fhs_launcher.sh" = {
      executable = true;
      text = ''
        #!/usr/bin/env bash
        ${tresoritFHS}/bin/tresorit-fhs -c "${config.home.homeDirectory}/.local/share/tresorit/tresorit --hidden" > ${config.home.homeDirectory}/.local/share/tresorit/fhs.log 2>&1 &
      '';
    };
  };

  # Home Manager can also manage your environment variables through
  # 'home.sessionVariables'. These will be explicitly sourced when using a
  # shell provided by Home Manager. If you don't want to manage your shell
  # through Home Manager then you have to manually source 'hm-session-vars.sh'
  # located at either
  #
  #  ~/.nix-profile/etc/profile.d/hm-session-vars.sh
  #
  # or
  #
  #  ~/.local/state/nix/profiles/profile/etc/profile.d/hm-session-vars.sh
  #
  # or
  #
  #  /etc/profiles/per-user/nicky/etc/profile.d/hm-session-vars.sh
  #
  home.sessionVariables = {
    #CLAUDE_INSTANCE = "A";
    # Sonnet default; using Opus must be a deliberate choice via --model
    ANTHROPIC_MODEL = "claude-sonnet-4-6";
    MOZ_ENABLE_WAYLAND = 1; # for Firefox in Wayland sessions
    ZAI_CODING_PLAN_API_KEY = secrets.ZAI_CODING_PLAN_API_KEY or "";
    DEEPSEEK_API_KEY = secrets.DEEPSEEK_API_KEY or "";
  };
  home.shellAliases = {
  };

  programs = {
    bash = {
      enable = true;
      initExtra = ''
        # Unset guard to ensure PATH additions are applied even if
        # hm-session-vars.sh was already sourced (e.g., by .profile)
        unset __HM_SESS_VARS_SOURCED
        . "${config.home.profileDirectory}/etc/profile.d/hm-session-vars.sh"

        # Bracketed paste — treat pasted text as single buffer, not executed line-by-line
        if [[ $TERM_PROGRAM == vscode ]]; then
          bind 'set enable-bracketed-paste on'
        fi
      '';
    };
    direnv = {
      enable = true;
      enableBashIntegration = true;
      nix-direnv.enable = true;
    };
    git = {
      enable = true;
      lfs = {
        enable = true;
      };
      # maintenance = {
      #   enable = true;
      # };
      package = pkgs.gitFull; # The git package to use. Use pkgs.gitFull to gain access to git send-email for instance. # Also for some features related to git-maintenance on git remotes used with ssh.
      settings.user.name = "Yannick Loth";
      settings.user.email = "727881+yannickloth@users.noreply.github.com";
    };
    # Let Home Manager install and manage itself.
    home-manager.enable = true;
    uv = {
      enable = true;
    };
    # Merged from the previous nicky-hm.nix config
    firefox = {
      enable = true;
      policies = {
        # Pre-98 behavior: opened files go to a temp dir; Downloads only on explicit save.
        StartDownloadsInTempDirectory = true;
      };
    };
    chromium = {
      commandLineArgs = [
        "--enable-features=VaapiVideoDecodeLinuxGL"
        "--ignore-gpu-blocklist"
        "--enable-zero-copy"
      ];
      enable = true;
    };
    command-not-found = {
      enable = true;
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
          type = "viml";
        }
        YankRing-vim
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
    # Merged from the previous nicky-hm.nix config
    kdeconnect = {
      enable = true;
      indicator = true;
    };
    psd = { # Settings of the profle-sync-daemon service. Puts browser profiles into tmpfs or overlayfs/overlay for improved performance.
      enable = true;
    };
    syncthing = {
      enable = true;
      tray = {
        enable = false;
      };
    };
  };

  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 14d";
  };

  systemd.user.services = {
    nestor-mount = {
      Unit = {
        Description = "Mount nestor NAS (Tailscale) via Rclone";
        After = [ "network-online.target" ];
      };
      Install = {
        WantedBy = [ "default.target" ];
      };
      Service = {
        # Use full paths to be safe in systemd units
        ExecStartPre = "${pkgs.coreutils}/bin/mkdir -p %h/nestor";
        ExecStart = ''
          ${pkgs.rclone}/bin/rclone mount nestor:/ /home/${config.home.username}/nestor \
          --vfs-cache-mode writes \
          --allow-other \
          --network-mode
        '';
        # CachyOS/Arch uses fusermount3
        ExecStop = "/usr/bin/fusermount3 -u %h/nestor";
        Restart = "on-failure";
        RestartSec = "15s";
      };
    };

  };
  xdg.userDirs = {
          createDirectories = false;
          enable = true;
          desktop = "/home/nicky/sync/yannick/LaptopSync/Desktop/";
          documents = "/home/nicky/sync/yannick/LaptopSync/Documents/";
          download = "/home/nicky/sync/yannick/LaptopSync/Downloads/";
          music = "/home/nicky/sync/yannick/LaptopSync/Music/";
          pictures = "/home/nicky/sync/yannick/LaptopSync/Pictures/";
          publicShare = "/home/nicky/sync/yannick/LaptopSync/Public/";
          templates = "/home/nicky/sync/yannick/LaptopSync/Templates/";
          videos = "/home/nicky/sync/yannick/LaptopSync/Videos/";
        };
}
