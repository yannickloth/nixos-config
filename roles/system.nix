# Common system configuration shared by all hosts.
# Imported from each host's <host>-configuration.nix.
# Host-specific packages live in the host configuration files.

{ config, pkgs, lib, ... }:

let
  # Install the Master PDF Editor (disabled per-host via
  # `system.masterPdfEditor.enable = false`).
  masterPdfEditor = pkgs.masterpdfeditor.overrideAttrs (old: rec {
    pname = "masterpdfeditor";
    version = "5.8.70";
    src = pkgs.fetchurl {
      url = "https://code-industry.net/public/master-pdf-editor-${version}-qt5.x86_64.tar.gz";
      sha256 = "sha256-mheHvHU7Z1jUxFWEEfXv2kVO51t/edTK3xV82iteUXM=";
    };
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
      install -Dm644 license.txt $out/share/$name/LICENSE
      ln -s $p/masterpdfeditor5 $out/bin/masterpdfeditor5
      cp -v -r stamps templates lang fonts $p

      runHook postInstall
    '';
  });
in {
  imports = [
    ../services/system.nix
  ];

  options.system.masterPdfEditor = {
    enable = lib.mkEnableOption "the Master PDF Editor" // { default = true; };
  };

  config = {
    # Allow unfree packages
    nixpkgs.config.allowUnfree = true;
    # openclaw is marked insecure by nixpkgs (LLM-based agent parses untrusted
    # content with full system access); explicitly accepted by the user.
    # NOTE: `nixpkgs.config.permittedInsecurePackages` does NOT merge across
    # modules — the last definition silently wins. Keep ALL entries here;
    # do not set the option elsewhere (electron: xps, dotnet: naps2/scanning).
    nixpkgs.config.permittedInsecurePackages = [
      "openclaw-2026.5.7"
      "electron-36.9.5"
      "dotnet-sdk-6.0.428"
    ];
    home-manager.useGlobalPkgs = true; # with this, HomeManager will use the same pkgs config as nixos, amongst others the same value for config.allowUnfree

    environment.systemPackages = with pkgs; [
      micro #vim -> use neovim instead, with home manager # Do not forget to add an editor to edit configuration.nix! The Nano editor is also installed by default.
      wget
      bash
      kmod
      nixpkgs-fmt

      ### general purpose command-line tools
      age # simple, modern file encryption (rage is available in the dev shell)
      binutils
      bottom
      cht-sh # command-line cheat sheet
      fastfetch # system information summary
      #fcp # Significantly faster alternative to the classic Unix cp(1) command
      fd # finder
      fzf # fuzzy finder (Ctrl-R history search, Ctrl-T file pick, Alt-C cd)
      fzy # fuzzy finder
      zoxide # smart `z` cd: jump to frequently-visited directories
      hex # color hexdump
      inotify-tools # inotify-tools is a C library and a set of command-line programs for Linux providing a simple interface to inotify.
      iw # Wireless interface config tool using nl80211.
      jq # JSON processor
      # ripgrep-all # ripgrep also file contents
      restic # fast, secure backup program
      rm-improved
      unzip
      yq-go # YAML/XML/TOML processor
      nix-output-monitor # pretty rebuild monitor (`nom build`); also in dev shell
      ###

      ### for hardware info
      clinfo
      dmidecode
      lm_sensors # CPU/temperature sensor readings (`sensors`)
      mesa-demos
      nvme-cli # NVMe SSD health and management (`nvme smart-log`)
      pciutils
      powertop # power consumption analysis (`powertop`); auto-tune intentionally not enabled
      s-tui # terminal UI for CPU temp/frequency/power monitoring
      smartmontools # disk/SSD health via SMART (`smartctl -a /dev/sda`)
      stress-ng # system stress testing (paired with s-tui for thermals)
      usbutils
      vulkan-tools
      wayland-utils
      ###

      direnv # for lorri
      nix-direnv # for direnv
      distrobox
      eid-mw
      fuse3
      fuseiso
      #geogebra
      #geogebra6
      #gitFull
      gnome-tweaks
      gparted
      htop
      killall
      # kdePackages.kig
      kdePackages.kfind
      mpv
      nixd # Nix language server
      openclaw # self-hosted AI assistant/agent (https://openclaw.ai)
      nixdoc # Generate documentation for Nix functions
      ocrmypdf
      p7zip # A new p7zip fork with additional codecs and improvements
      pandoc
      qpwgraph # PipeWire graph manager
      shellcheck # Shell script analysis tool
      smplayer
      usbutils
      virt-manager
      virtiofsd
    ] ++ lib.optional config.system.masterPdfEditor.enable masterPdfEditor
    ++ [
      #     (softmaker-office.override {
      #       officeVersion = {
      # #         # 2018
      # #         edition = "2018";
      # #         version = "982";
      # #         hash = "sha256-A45q/irWxKTLszyd7Rv56WeqkwHtWg4zY9YVxqA/KmQ=";
      #         # 2021
      #         edition = "2021";
      #         version = "1064";
      #         hash = "sha256-UyA/Bl4K9lsvZsDsPPiy31unBnxOG8PVFH/qisQ85NM=";
      #       };
      #     })
      # (pkgs.callPackage ./packages/applications/office/softmaker/softmaker_office.nix {
      #   officeVersion = {
      #     edition = "2024";
      #     version = "1204";
      #     hash = "sha256-E58yjlrFe9uFiWY0nXoncIxDgvwXD+REfmmdSZvgTTU=";
      #   };
      # })
      # (pkgs.callPackage ../packages/applications/office/softmaker/softmaker_office.nix {
      #   officeVersion = {
      #     edition = "2024";
      #     version = "1222";
      #     hash = "sha256-eyYBK5ZxPcBakOvXUQZIU2aftyH6PXh/rtqC/1BJhg4=";
      #   };
      # })
      xdg-utils

      ### Networking tools
      dig
      firewalld
      firewalld-gui
      inetutils # for ping6
      netcat-gnu

      ### LibreOffice
      libreoffice-qt
      #libreoffice-fresh
      hunspell
      hunspellDicts.nl_nl
      hunspellDicts.fr-moderne
      hunspellDicts.es-es
      hunspellDicts.en-us
      hunspellDicts.en_GB-large
      hunspellDicts.de-de
      ###

      ### for Tresorit distrobox:
      fusePackages.fuse_2
      libxcb
      libX11
      libXext
      libXfixes
      libXrandr
      xcbutil
      xcbutilimage
      xcbutilkeysyms
      xcbutilrenderutil
      xcbutilwm
      libGL
      libGLU
      libxkbcommon
      patchelf
      ###
    ];

    environment.sessionVariables = {
      MOZ_USE_XINPUT2 = "1"; # Makes Firefox use xinput2. This improves touchscreen support, enables additional touchpad gestures and enables smooth scrolling as opposed to the stepped scrolling that Firefox has by default.
    };

    programs = {
      bash = {
        completion.enable = true;
        #      interactiveShellInit= ''
        #        eval "$(direnv hook bash)"
        #      '';
      };
      command-not-found.enable = true; # Whether interactive shells should show which Nix package (if any) provides a missing command.
      firefox = {
        enable = true;
        policies = {
          # Pre-98 behavior: opened files go to a temp dir; Downloads only on explicit save.
          StartDownloadsInTempDirectory = true;
        };
        languagePacks = [
          "de"
          "en-GB"
          "fr"
        ];
        nativeMessagingHosts.packages = [
          pkgs.web-eid-app
        ];
        # package=pkgs.librewolf;
      };
      nano = {
        nanorc = ''
          set autoindent
          set historylog
          set indicator
          set linenumbers
          set mouse
          set nowrap
          set tabstospaces
          set tabsize 2
        '';
      };
      partition-manager.enable = true; # Whether to enable KDE Partition Manager.
    };

    services = {
      # Firmware update daemon (`fwupdmgr refresh && fwupdmgr update`);
      # KDE Plasma surfaces it in Discover's updates view.
      fwupd.enable = true;
      # SMART monitoring daemon: watches disk health and logs/alerts on
      # degradation. Complements the `smartmontools` package (smartctl).
      smartd.enable = true;
    };

    xdg.portal = {
      enable = true; # Whether to enable xdg desktop integration.
      #     extraPortals = [
      #       pkgs.xdg-desktop-portal-gtk
      #       pkgs.xdg-desktop-portal-wlr
      #     ];
      xdgOpenUsePortal = true; # Sets environment variable NIXOS_XDG_OPEN_USE_PORTAL to 1 This will make xdg-open use the portal to open programs, which resolves bugs involving programs opening inside FHS envs or with unexpected env vars set from wrappers. See #160923 for more info.
    };
  };
}
