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

    litellm # Use any LLM as a drop in replacement for gpt-3.5-turbo. Use Azure, OpenAI, Cohere, Anthropic, Ollama, VLLM, Sagemaker, HuggingFace, Replicate (100+ LLMs)

    jdk25 # Java 25
    elan # Lean theorem prover version manager

    rclone # Used to mount nestor shares
    # fuse3 # Already installed as a CachyOS package.

    # LLM inference — llama.cpp replaces Ollama (1.8x faster for local models)
    (llama-cpp.override { cudaSupport = true; }) # llama.cpp inference server with CUDA (OpenAI-compatible API via llama-server)
    open-webui

    quarto
    # panache

    jbang

    tresoritFHS
  ];
  # Configure npm to use a writable directory for global packages
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

    # Install MCP llama.cpp server via npm (replaces ollama-mcp)
    # $DRY_RUN_CMD ${pkgs.nodejs}/bin/npm install -g mcp-llama-cpp@latest -> DOES NOT EXIST

    # Install Cline to use Cline Kanban
    $DRY_RUN_CMD ${pkgs.nodejs}/bin/npm install -g cline
  '';

  home.activation.cleanupOllama = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    # Clean up old Ollama model blobs (now replaced by llama.cpp GGUF models)
    if [ -d "$HOME/.ollama" ]; then
      echo "Removing old Ollama data (~88GB)..."
      $DRY_RUN_CMD rm -rf "$HOME/.ollama"
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
    ANTHROPIC_BASE_URL = "http://127.0.0.1:8787";
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

    # llama.cpp inference server (replaces Ollama — 1.8x faster)
    llama-server = {
      Unit = {
        Description = "llama.cpp inference server (CUDA, OpenAI-compatible API)";
        After = [ "network-online.target" ];
      };
      Install = {
        WantedBy = [ "default.target" ];
      };
      Service = let
        llama-cpp-cuda = pkgs.llama-cpp.override { cudaSupport = true; };
        modelDir = "${config.home.homeDirectory}/.local/share/llama.cpp/models";
      in {
        # This replaces taskset and pins the service to the P-cores (0-15)
        CPUAffinity = "0-15";
        ExecStart = ''
          ${llama-cpp-cuda}/bin/llama-server \
            --model ${modelDir}/qwen3-coder-30b-a3b-q4_k_m.gguf \
            --alias qwen3-coder-30b-a3b-q4_k_m \
            --host 0.0.0.0 \
            --port 8090 \
            --n-gpu-layers 10 \
            --ctx-size 32768 \
            --flash-attn on \
            --cache-type-k q4_0 \
            --cache-type-v q4_0 \
            --threads 8 \
            --metrics
        '';
        Restart = "on-failure";
        RestartSec = "10s";
        Environment = [
          "CUDA_VISIBLE_DEVICES=0"
          "LD_LIBRARY_PATH=/usr/lib:/usr/lib64:/usr/lib/nvidia"
        ];    
      };
    };

    # OpenWebUI service (now points to llama-server instead of Ollama)
    open-webui = {
      Unit = {
        Description = "OpenWebUI web interface";
        After = [
          "network-online.target"
          "llama-server.service"
        ];
        Wants = [ "llama-server.service" ];
      };
      Install = {
        WantedBy = [ "default.target" ];
      };
      Service = {
        ExecStart = "${pkgs.open-webui}/bin/open-webui serve";
        Restart = "on-failure";
        RestartSec = "30s";
        Environment = [
          "OPENAI_API_BASE_URL=http://localhost:8080/v1"
          "WEBUI_SECRET_KEY=nicky-secret-key"
          "DATA_DIR=${config.home.homeDirectory}/.local/share/open-webui/data"
        ];
      };
    };

    # Pino proxy - Anthropic API cache optimizer for Claude Code
    pino-proxy = {
      Unit = {
        Description = "Pino proxy - Anthropic API cache optimizer";
        After = [ "network-online.target" ];
      };
      Install = {
        WantedBy = [ "default.target" ];
      };
      Service = let
        pino-src = pkgs.fetchFromGitHub {
          owner = "alxsuv";
          repo = "pino";
          rev = "e2bebcf5241fb91facec18a8dcd2970864e6b18e";
          sha256 = "sha256-a2QtaqRgoRuNQ3CP7vjgNPaQJIvymrybcJeTtUjmma8=";
        };
      in {
        WorkingDirectory = pino-src;
        ExecStart = "${pkgs.nodejs}/bin/node ${pino-src}/bin/pino-proxy.js";
        Environment = [
          "AUTO_CACHE=1"
          "TRANSFORM_FILE=${pino-src}/src/transforms/default.js"
          "DROP_TOOLS=NotebookEdit,CronCreate,CronDelete,CronList,RemoteTrigger,PushNotification,Monitor"
          "LOG_BODIES=1"
        ];
        Restart = "on-failure";
        RestartSec = "10s";
      };
    };
  };
}
