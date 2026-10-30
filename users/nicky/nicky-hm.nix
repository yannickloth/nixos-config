# Standalone home-manager config for nicky.
# Build/apply via the consolidated flake: home-manager switch --flake ~/code/nixos-config/users
# (or per-host via the main flake's home-manager.users.nicky).
#
{ config
, pkgs
, lib
, ...
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
  # True when this config targets laptop-p16, carried via commonHm.hostName.
  # That option is set by the standalone flake (users/flake.nix, used on
  # CachyOS) and by the NixOS host (hosts/laptop-p16/laptop-p16.nix). Note
  # config.networking.hostName is NOT reachable inside home-manager modules
  # (they expose their own config namespace), so it cannot be used here.
  isP16 = config.commonHm.hostName == "laptop-p16";
  # True when this config is built by the standalone CachyOS flake
  # (users/flake.nix). On CachyOS the engine's host tuning lives in /etc
  # (hosts/laptop-p16/cachyos/), because no NixOS system module runs there; on
  # the NixOS host it is provided by hosts/laptop-p16/ instead. Gating keeps
  # the CachyOS-only activation out of a future NixOS install.
  isCachyOS = config.commonHm.isCachyOS;
  # Runtime path of nicky's agenix-decrypted AI-chat API keys (see age.secrets).
  nickyApiKeysPath = config.age.secrets."nicky.nix".path;
in
{
  imports = [
    ../common-hm.nix
    ../emacs-adult.nix
    ../../packages/strata/home.nix
    ../../packages/unsloth-studio/home.nix
    ../natural-scroll.nix
    ../opencode.nix
    ../../packages/orca/home.nix
    ../../packages/browseros/home.nix
    ../../packages/libreoffice-mcp/home.nix
    ../../packages/opencode-desktop/home.nix
    ../../packages/rea/home.nix
    ../../packages/herdr/home.nix
  ];

  # Global opencode provider/model config (deepseek, Z.AI GLM Coding Plan
  # subscription, Kimi, Hetzner).
  opencode.enable = true;
  # On CachyOS there is no system agenix / /etc/secrets, so source the provider
  # keys from the home-manager agenix secret decrypted with ~/.ssh/agenix_nicky
  # (see the `age` block below). On NixOS hosts keep the default /etc/secrets.
  opencode.envFile =
    lib.mkIf config.commonHm.isCachyOS config.age.secrets."open-webui.env".path;

  # Orca (agent development environment): the desktop client on every host, and
  # on laptop-p16 the single always-on runtime server (`orca-ide serve`) that
  # other clients pair to over Tailscale. Per-user: it runs as nicky, so the
  # agent CLIs it drives use nicky's PATH and credentials.
  orca.enable = true;

  # BrowserOS neo: agent-driven browser for AI assistants (MCP), runs with the
  # user's real logins in its own profile.
  browseros.enable = true;

  # LibreOffice MCP extension (packages/libreoffice-mcp): an MCP server runs
  # inside the open LibreOffice window on https://localhost:8765/mcp (the
  # default port; aeiuno uses 8766 so parallel sessions cannot attach to each
  # other's documents), so agents edit the document the user is looking at.
  # Registered in users/opencode.nix.
  libreofficeMcp.enable = true;
  # Same build as the app in home.packages (libreoffice-qt6, not pkgs.libreoffice
  # default): `unopkg` must come from the LibreOffice that actually runs, so the
  # extension registers into the profile that build reads.
  libreofficeMcp.libreoffice = pkgs.libreoffice-qt6;

  # opencode Desktop: the GUI of the opencode v2 line, next to the `opencode`
  # CLI in home.packages below. Both read ~/.config/opencode; the desktop app
  # runs its own bundled agent server.
  opencode-desktop.enable = true;

  # REA: reverse-engineering MCP server + CLI (packages/rea/home.nix) and the
  # "reverse-engineer-anything" agent skill.
  rea.enable = true;

  # herdr (packages/herdr/home.nix): terminal multiplexer / runtime for coding
  # agents, plus its agent skill and the integrations for the agents installed
  # here (opencode, pi, hermes) — those `herdr integration install` runs happen
  # at activation, see the module.
  herdr.enable = true;
  orca.server = lib.mkIf isP16 {
    enable = true;
    # No Tailscale address pinned: the launcher derives it at start.
  };

  # Laya is gone entirely: package, flake output, home/nixos modules, the
  # laya-mcp user service and the (gated) opencode MCP entry all removed. It was
  # disabled since 2026-09-28, and Unsloth Studio's Decision API already serves
  # the same System One shape locally — POST /v1/systemone and the
  # /mcp/decisions MCP mount, the latter registering as opencode's `systemone`
  # server — so a second engine with its own checkpoint, venv and port had
  # nothing left to add. Recoverable from git if it is ever wanted back.

  # CLM is gone entirely: package, flake output, module and service units all
  # removed. Unsloth Studio's Decision API serves the same System 1 shape
  # locally — POST /v1/systemone plus the /mcp/decisions MCP mount — and runs
  # the model on CPU, so a separate stack (Qwen3-8B pooling encoder wanting
  # ~17 GB of VRAM on top of Strata and Studio, plus a 75 MB head on
  # clm-serve) had nothing left to add here. It was never provisioned either:
  # no ~/.local/share/clm venv ever existed, so both units sat installed and
  # inactive. Recoverable from git if the engine is ever wanted back.

  # Unsloth Studio on every host (packages/unsloth-studio/home.nix): the
  # local inference UI/API and — the reason it left its laptop-p16-only gate
  # — the Decision API, which serves open System One models (Laya, ...) on a
  # TypeSafe-compatible /v1/systemone. This is the local decisional endpoint:
  # the opencode `systemone` MCP reaches it through the native /mcp/decisions
  # mount, and the systemone plugin (llm-harness-plugins/systemone) posts its
  # packaged judgments to /v1/systemone. Its model and device live in Studio's DB
  # panel, not here; that module's header records why the env overrides are
  # deliberately unset.
  # ONE instance per host: Studio installs per-user into $HOME and binds
  # :8888, so aeiuno does not enable it — her opencode reaches the same
  # localhost endpoint. Hosts set users.users.nicky.linger = true so the API
  # survives logout.
  unsloth-studio.enable = true;
  # On the Strata host, pin Studio's llama-server to the handoff wrapper so
  # picking a model unloads the 125B engine before VRAM is computed (the other
  # hosts have no `strata` unit and no llama.cpp tree yet, where a pinned path
  # would only get in discovery's way).
  unsloth-studio.strataGpuHandoff = isP16;

  # Strata (Qwen3.8-Flash-Next 125B MoE inference, OpenAI/Anthropic API on
  # localhost). GPU-gated to laptop-p16: the engine is built for the
  # A3000's sm_86 and the runtime wants its 12 GB of VRAM plus 34-50 GB of
  # RAM for the expert arena. First `strata` run downloads the ~70-84 GB
  # model into ~/.local/share/strata (STRATA_HOME overrides the directory).
  # Strata (Qwen3.8-Flash-Next 125B MoE) — re-enabled 2026-09-28: measured
  # against Unsloth Studio on the same model (IQ2_XS, expert offload),
  # Studio produces ~2 tok/s vs Strata's ~6 tok/s — Strata's MTP speculative
  # decoding + expert cache + PLE are worth 3x here. Studio keeps the fast 9B
  # and 27B models; Strata is the 125B endpoint. The model files live in
  # Studio's HF cache and are symlinked into ~/.local/share/strata/models/,
  # so both tools read the same bytes (no duplicate disk). See
  # packages/strata/engine.nix for the full measurement matrix.
  # Hardware tuning measured on this laptop by tools/calibrate.py (see the
  # bench/results/2026-10-02-rtx-a3000-i7-12850hx entry in forks-Strata):
  #   --pcie-frac 0.35  beats the 0.55 default and the probe's 0.12-0.15
  #                     (32.7 vs 27.0 tok/s for the 0.12 the probe picks)
  #   --spec-min-p 0.70 beats 0.5 (34.0 vs 31.5 tok/s; slower CPU, no AVX-512)
  #   --pool-workers 15 (the engine default) beats 8 on the fresh path: the
  #                     E-cores add pool capacity here, they are not a tail
  #                     (P2 re-measure, ops/p2-pool-affinity-results.md)
  #   --kv-resident 20480 (was 32768): frees ~90 expert-cache slots; P8 measured
  #                     the warm hit rate 0.618 -> 0.632 and fewer refusals,
  #                     costing extra pinned-RAM KV reads only past ~20k context
  #   --adapt-every 1   (was 4): learns a cold conversation's hot experts faster
  #                     (fresh hit 0.468 -> 0.539 at a small warm-turn trade)
  #                     (P8, ops/issues/p8-reduce-misses.md)
  # Enforced on every config the package writes, so setup cannot undo them.
  # enable stays gated on laptop-p16 (isP16).
  strata = lib.mkIf isP16 {
    enable = true;
    # Keep the engine resident far longer than the 5-minute default: a reload
    # puts the weights back in VRAM in ~27-30 s before decode can start, and at
    # the old 300 s every >5-minute gap cost that stall. 900 s holds ~55 GB of
    # RAM and most of the GPU idle between turns instead — the trade-off is
    # explicitness over latency, so lower it if another GPU job needs the card.
    idleUnloadSeconds = 900;
    # Vision is not the default: using the strata-vision image encoder drops
    # throughput from ~35 to ~22 tok/s. The ENCODER is still built and shipped
    # (visionEncoder), so `strata --setup` asks the images question and both
    # answers work instead of failing on a package without the binary. Answer
    # that prompt explicitly - upstream's default is "y" - and the cost of
    # shipping the encoder is disk only.
    vision = false;
    visionEncoder = true;
    # The desktop app (upstream AppImage): shares the models below and can
    # either load one with its own engine or use the API of a running server -
    # e.g. add http://127.0.0.1:8080/v1 as a custom connection. Nothing is
    # stopped on launch (stopServerOnLaunch) for that reason.
    desktop.enable = true;
    pcieFrac = 0.35;
    specMinP = 0.70;
    poolWorkers = 15;
    kvResident = 20480;
    adaptEvery = 1;
    # Prompt-cache tail checkpoint (bench 2026-10-14, arms of
    # /tmp/opencode/strata-ab.sh.py): without it, serve-side checkpoint reuse
    # caps at the kv-resident window (20480), so every request re-reads
    # `context - 20480` tokens (~118 s at a 130K agent conversation). With it
    # the re-read is bounded ~12-13K tokens (~13 s flat at 20-48K context;
    # 47K turn: 31.4 s -> 12.5 s). The parked-conversation cache
    # (--conversation-cache-mib) measured ~15% slower with no reuse gain in
    # single-conversation flow, so it stays off.
    promptCacheTail = true;
    # The other half of the Studio handoff (packages/unsloth-studio/home.nix
    # frees the card FROM Strata FOR Studio; these free it FROM Studio FOR
    # Strata). Naming a Strata model while Studio holds the card must not end
    # in a failed cudaMalloc: beforeLoad asks Studio to unload its own model
    # first, and minFreeVramMib is the backstop that refuses the load (503 +
    # Retry-After) if VRAM is still short after the hook. idleUnloadSeconds
    # above is 900, so Strata holds the card deliberately long - a Studio turn
    # inside that window is exactly the case this covers.
    minFreeVramMib = 8000;
    beforeLoad = "${config.home.homeDirectory}/.local/bin/unsloth-studio-unload.sh";
    # STRATA_ADAPT_OVERLAP stays at the upstream default (off): 0.1.43 defaulted
    # it on for Linux CUDA, which cost ~2.7x decode on this rig (small expert
    # cache, --adapt-every 1), and 0.1.43.1 made it opt-in again. The interleaved
    # A/B on 0.1.44.1 (2026-10-16, see packages/strata/default.nix) measured the
    # flag a wash here, so no engineEnv override is set; re-add one to re-test
    # after an engine change.
  };

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

    (pkgs.callPackage ../../packages/masterpdfeditor { })
    obsidian

    languagetool
    opencode
    pi-coding-agent
    hermes-agent
    magpie
    deepseek-harness

    jdk25 # Java 25
    elan # Lean theorem prover version manager

    rclone # Used to mount nestor shares
    fuse3 # provides fusermount3, used by the nestor-mount unit below

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
    gparted
    hunspellDicts.fr-any
    hunspellDicts.en_US-large
    hunspellDicts.en_GB-large
    hunspellDicts.de_DE
    inkscape-with-extensions
    jetbrains-toolbox
    kdePackages.dolphin
    kdePackages.elisa
    kdePackages.filelight
    kdePackages.gwenview
    kdePackages.kalk
    kdePackages.kate
    kdePackages.okular
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
    keepassxc
    kid3-qt # A simple and powerful audio tag editor
    kodi
    krita
    gnuplot # Command-line plotter for computed numbers (functions, data)
    # Qt6/KDE build of the same 25.8.5.2: the plain `libreoffice` ships only the
    # gen+gtk3 VCL plugins, so on this Wayland/KDE session it reads the user's
    # dark GTK theme (adw-gtk3-dark) even though Plasma is BreezeLight, and its
    # "Application Colors = Automatic" then resolves to dark. The qt6 build has
    # --enable-qt6, follows the Plasma colour scheme, and keeps native Wayland +
    # KDE dialogs. libreofficeMcp.libreoffice must match it (see below).
    libreoffice-qt6
    lua
    lutris
    mastodon
    maxima # Computer algebra system: integrate, solve, limit, sum, ODEs (CLI `maxima`)
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
        # Install Tresorit if not already installed. The installer is fetched
        # by Nix at build time (pinned hash) instead of downloaded from a
        # mutable URL at activation: reproducible, MITM-proof, and it does not
        # silently change between switches. It is copied to a private temp file
        # (never a predictable /tmp path a local user could pre-create), and a
        # failure only warns instead of aborting the whole switch.
        TRESORIT_INSTALLER=${pkgs.fetchurl {
          url = "https://installer.tresorit.com/tresorit_installer.run";
          sha256 = "0xpw9a07hq5fxw6zb30csafz7kchpb257wag61sc271prax303zk";
        }}
        if [ ! -f "$HOME/.local/share/tresorit/tresorit" ]; then
          echo "Installing Tresorit..."
          installer=$(${pkgs.coreutils}/bin/mktemp)
          $DRY_RUN_CMD ${pkgs.coreutils}/bin/cp "$TRESORIT_INSTALLER" "$installer"
          $DRY_RUN_CMD chmod +x "$installer"
          if ! $DRY_RUN_CMD "$installer" --target "$HOME/.local/share/tresorit" --noexec; then
            echo "setupTresorit: installer failed; leaving Tresorit uninstalled" >&2
          fi
          $DRY_RUN_CMD rm -f "$installer"
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

  # CachyOS: the Strata engine needs a 2 MiB hugetlb pool covering its whole
  # ~40 GiB arena, and an unlimited RLIMIT_MEMLOCK for the systemd user manager
  # (the strata unit's LimitMEMLOCK=infinity is capped at the manager's 8 MiB
  # otherwise). Both live in /etc, which home-manager cannot write. Apply the
  # bundled installer, but only non-interactively (`sudo -n`) so `home-manager
  # switch` never blocks: run `sudo -v` beforehand to have it applied, else it
  # prints the one command. The future NixOS install uses hosts/laptop-p16/
  # instead and never runs this (isCachyOS is false there).
  home.activation.strataHostTuning = lib.mkIf (isP16 && isCachyOS)
    (lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      setup=${../../hosts/laptop-p16/cachyos}
      if [ "$(cat /proc/sys/vm/nr_hugepages 2>/dev/null || echo 0)" -lt 20480 ] \
         || [ ! -e /etc/systemd/system/user@.service.d/99-strata-memlock.conf ]; then
        if sudo -n true 2>/dev/null; then
          $DRY_RUN_CMD sudo "$setup/install.sh"
        else
          echo "strata: host tuning not installed; run once: sudo $setup/install.sh" >&2
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
    MOZ_ENABLE_WAYLAND = "1"; # for Firefox in Wayland sessions
    # AI-chat API keys (ZAI_CODING_PLAN_API_KEY, DEEPSEEK_API_KEY) are sourced
    # at shell init from the agenix-decrypted file (see programs.zsh.initContent).
    # Pretty man pages via bat: strips the raw formatting and syntax-highlights
    # the man source. `-l man` tells bat the language, `-p` plain (no header).
    MANPAGER = "sh -c 'col -bx | bat -l man -p'";
  };
  home.shellAliases = { };

  # agenix (home-manager module): decrypt nicky's AI-chat API keys at activation
  # to $XDG_RUNTIME_DIR/agenix/nicky.nix, then sourced by the shell. The key is
  # ~/.ssh/agenix_nicky, whose public key is the `user-nicky` agenix recipient
  # (see secrets.nix and ssh-keys/users/nicky). ~/.ssh/id_ed25519 is nicky's
  # GitHub SSH identity and is NOT an agenix recipient, so it must not be used
  # here. A missing key fails the build loudly. See secrets-structure/README.md.
  age = {
    identityPaths = [ "/home/nicky/.ssh/agenix_nicky" ];
    secrets."nicky.nix" = {
      file = ../../secrets/nicky.nix.age;
      mode = "0400";
    };
    # Shared family provider keys (OPENAI_API_KEYS JSON), also mounted here so
    # opencode can materialize its per-provider key files on standalone
    # home-manager hosts with no system agenix (CachyOS). See opencode.envFile.
    secrets."open-webui.env" = {
      file = ../../secrets/open-webui.env.age;
      mode = "0400";
    };
  };

  programs = {
    zsh = {
      initContent = ''
        # Unset guard to ensure PATH additions are applied even if
        # hm-session-vars.sh was already sourced (e.g., by .profile)
        unset __HM_SESS_VARS_SOURCED
        . "${config.home.profileDirectory}/etc/profile.d/hm-session-vars.sh"

        # Source agenix-decrypted AI-chat API keys if present (see age.secrets).
        if [ -f "${nickyApiKeysPath}" ]; then
          set -a
          . "${nickyApiKeysPath}"
          set +a
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
        # No After=network-online.target: that unit lives in the system
        # manager and is invisible to user units. Restart=on-failure below
        # retries until Tailscale is up.
      };
      Install = {
        WantedBy = [ "default.target" ];
      };
      Service = {
        # Use full paths to be safe in systemd units
        ExecStartPre = "${pkgs.coreutils}/bin/mkdir -p %h/nestor";
        ExecStart = ''
          ${pkgs.rclone}/bin/rclone mount nestor:/ /home/${config.home.username}/nestor \
          --vfs-cache-mode writes
        '';
        # fusermount3 from the Nix closure (not /usr/bin: wrong on NixOS).
        ExecStop = "${pkgs.fuse3}/bin/fusermount3 -u %h/nestor";
        Restart = "on-failure";
        RestartSec = "15s";
      };
    };

  };

  xdg.configFile."user-dirs.dirs".force = true;

  # XDG dirs live directly inside nicky's syncthing folder (/sync/yannick via
  # the ~/sync symlink), the same layout used for aeiuno (christine), sven and
  # aaron. KDE/Plasma and xdg-user-dirs pick these up; content is synced across
  # the laptops and replicated to nestor.
  xdg.userDirs = {
    createDirectories = false;
    enable = true;
    setSessionVariables = true; # keep legacy default
    desktop = "/home/nicky/sync/yannick/Desktop/";
    documents = "/home/nicky/sync/yannick/Documents/";
    download = "/home/nicky/sync/yannick/Downloads/";
    music = "/home/nicky/sync/yannick/Music/";
    pictures = "/home/nicky/sync/yannick/Pictures/";
    projects = "/home/nicky/sync/yannick/Projects/";
    publicShare = "/home/nicky/sync/yannick/Public/";
    templates = "/home/nicky/sync/yannick/Templates/";
    videos = "/home/nicky/sync/yannick/Videos/";
  };
}
