# Standalone home-manager config for nicky.
# Build/apply via the consolidated flake: home-manager switch --flake ~/code/nixos-config/users
# (or per-host via the main flake's home-manager.users.nicky).
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
  # AI-chat API keys live in the gitignored secrets/ folder (see
  # secrets-structure/README.md). Fall back to empty when absent.
  secrets = if builtins.pathExists /home/nicky/code/nixos-config/secrets/nicky.nix
            then import /home/nicky/code/nixos-config/secrets/nicky.nix
            else {};
  # True when this config targets laptop-p16, carried via commonHm.hostName.
  # That option is set by the standalone flake (users/flake.nix, used on
  # CachyOS) and by the NixOS host (hosts/laptop-p16/laptop-p16.nix). Note
  # config.networking.hostName is NOT reachable inside home-manager modules
  # (they expose their own config namespace), so it cannot be used here.
  isP16 = config.commonHm.hostName == "laptop-p16";
in
{
  imports = [
    ../common-hm.nix
    ../natural-scroll.nix
  ];

  # Enable the shared developer tools (neovim, vscode, direnv, etc.)
  commonHm.enableDeveloperTools = true;

  # Home Manager needs a bit of information about you and the paths it should
  # manage.
  home.username = "nicky";
  home.homeDirectory = "/home/nicky";

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
    digikam # photo management / organizer
    fd
    jq
    lsd
    netcat
    nil # Nix Language Server
    ripgrep
    tree # Command to produce a depth indented directory listing
    typst # New markup-based typesetting system that is powerful and easy to learn
    jetbrains-toolbox # JetBrains IDEs (IntelliJ, PyCharm, ...) via Toolbox
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
    opencode
    pi-coding-agent

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
    lutris
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
    vlc # native media player (parents only; kids use the gated flatpak)
    libmicrodns # for playing from VLC onto ChromeCast
    protobuf # for playing from VLC onto ChromeCast
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

  # Add local bin, npm global bin, and elan to PATH
  home.sessionPath = [
    "$HOME/.local/bin"
    "$HOME/.elan/bin"
    "$HOME/.npm-global/bin"
  ];

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

  # Install Unsloth Studio (browser-based LLM inference web UI + API server)
  # on laptop-p16 only. Not packaged in nixpkgs, so install imperatively from
  # the official installer script (same pattern as Tresorit above). The
  # resulting `unsloth` CLI + Studio UI live under ~/.unsloth.
  #
  # Gated at build time by `isP16` (see let). The extra runtime `hostname`
  # guard is belt-and-suspenders so a mis-targeted build can never install on
  # the wrong machine.
  home.activation.installUnsloth = lib.mkIf isP16 (lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    if [ "$(hostname)" = "laptop-p16" ]; then
      # install.sh puts the CLI at ~/.local/bin/unsloth and data under ~/.unsloth.
      if [ ! -x "$HOME/.local/bin/unsloth" ] && [ ! -d "$HOME/.unsloth" ]; then
        echo "Installing Unsloth Studio..."
        $DRY_RUN_CMD bash -c 'curl -fsSL https://unsloth.ai/install.sh | sh'
      fi
    fi
  '');

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
    # Unsloth Studio launcher (only defined on laptop-p16 builds; no-op guard).
    ".local/bin/unsloth-studio-launcher.sh" = lib.mkIf isP16 {
      executable = true;
      text = ''
        #!/usr/bin/env bash
        if [ "$(hostname)" != "laptop-p16" ]; then
          exit 0
        fi
        exec "$HOME/.local/bin/unsloth" studio -p 8888
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
    git = {
      enable = true;
      lfs = {
        enable = true;
      };
      # maintenance = {
      #   enable = true;
      # };
      #package = pkgs.git; # The git package to use. Use pkgs.gitFull to gain access to git send-email for instance. # Also for some features related to git-maintenance on git remotes used with ssh.
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
      configPath = "${config.xdg.configHome}/mozilla/firefox";
      policies = {
        # Pre-98 behavior: opened files go to a temp dir; Downloads only on explicit save.
        StartDownloadsInTempDirectory = true;
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

    # Run Unsloth Studio (LLM inference web UI + API) on laptop-p16 only,
    # gated at build time by isP16. The launcher also no-ops if ever run on a
    # non-p16 host.
    unsloth-studio = lib.mkIf isP16 {
      Unit = {
        Description = "Unsloth Studio - local LLM inference web UI";
        After = [ "network-online.target" ];
      };
      Install = {
        WantedBy = [ "default.target" ];
      };
      Service = {
        Type = "simple";
        ExecStart = "${config.home.homeDirectory}/.local/bin/unsloth-studio-launcher.sh";
        Restart = "on-failure";
        RestartSec = "15s";
      };
    };

  };
  xdg.userDirs = {
          createDirectories = false;
          enable = true;
          setSessionVariables = true; # keep legacy default
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
