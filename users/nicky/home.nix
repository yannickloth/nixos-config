# Symlink this file into ~/.config/home-manager/ : 
# ln -sf ~/code/nixos-config/users/nicky/home.nix ~/.config/home-manager/home.nix
{
  config,
  pkgs,
  lib,
  ...
}:

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
              pkgs.xorg.libX11
              pkgs.xorg.libXrandr
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

    litellm # Use any LLM as a drop in replacement for gpt-3.5-turbo. Use Azure, OpenAI, Cohere, Anthropic, Ollama, VLLM, Sagemaker, HuggingFace, Replicate (100+ LLMs)

    jdk25 # Java 25
    elan # Lean theorem prover version manager

    rclone # Used to mount nestor shares
    # fuse3 # Already installed as a CachyOS package.

    # Ollama and OpenWebUI
    ollama-cuda
    open-webui
  ];
  # Configure npm to use a writable directory for global packages
  home.file.".npmrc".text = ''
    prefix=${config.home.homeDirectory}/.npm-global
  '';

  # Add local bin (Claude Code native), npm global bin, and elan to PATH
  home.sessionPath = [
    "$HOME/.local/bin"
    "$HOME/.elan/bin"
    "$HOME/.npm-global/bin"
  ];

  home.activation.installClaudeTools = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    # Install Claude Code native binary (auto-updates itself)
    if [ ! -f "$HOME/.local/bin/claude" ]; then
      $DRY_RUN_CMD ${pkgs.curl}/bin/curl -fsSL https://claude.ai/install.sh | $DRY_RUN_CMD bash
    fi

    # Install claude-trace via npm
    export NPM_CONFIG_PREFIX="$HOME/.npm-global"
    $DRY_RUN_CMD ${pkgs.nodejs}/bin/npm install -g @mariozechner/claude-trace@latest
  '';

  # Home Manager is pretty good at managing dotfiles. The primary way to manage
  # plain files is through 'home.file'.
  home.file = {
    # # Building this configuration will create a copy of 'dotfiles/screenrc' in
    # # the Nix store. Activating the configuration will then make '~/.screenrc' a
    # # symlink to the Nix store copy.
    # ".screenrc".source = dotfiles/screenrc;

    # # You can also set the file content immediately.
    # ".gradle/gradle.properties".text = ''
    #   org.gradle.console=verbose
    #   org.gradle.daemon.idletimeout=3600000
    # '';
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
    opencode = {
      enable = true;
    };
    uv = {
      enable = true;
    };
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

    # Ollama service
    ollama = {
      Unit = {
        Description = "Ollama LLM service";
        After = [ "network-online.target" ];
      };
      Install = {
        WantedBy = [ "default.target" ];
      };
      Service = {
        ExecStart = "${pkgs.ollama-cuda}/bin/ollama serve";
        Restart = "on-failure";
        RestartSec = "30s";
        Environment = "OLLAMA_HOST=0.0.0.0";
      };
    };

    # OpenWebUI service
    open-webui = {
      Unit = {
        Description = "OpenWebUI web interface";
        After = [
          "network-online.target"
          "ollama.service"
        ];
        Wants = [ "ollama.service" ];
      };
      Install = {
        WantedBy = [ "default.target" ];
      };
      Service = {
        ExecStart = "${pkgs.open-webui}/bin/open-webui serve";
        Restart = "on-failure";
        RestartSec = "30s";
        Environment = [
          "OLLAMA_BASE_URL=http://localhost:11434"
          "WEBUI_SECRET_KEY=nicky-secret-key"
          "DATA_DIR=${config.home.homeDirectory}/.local/share/open-webui/data"
        ];
      };
    };
  };
}
