# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running ‘nixos-help’).

{ config, pkgs, lib, ... }:

{
  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It‘s perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = "23.05"; # Did you read the comment?

  imports =
    [
      # Include the results of the hardware scan.
      #<nixpkgs/nixos/modules/services/hardware/sane_extra_backends/brscan4.nix>
      #<home-manager/nixos>

      ./hosts/laptop-hera/laptop-hera.nix

      ./modules/systemPackages.nix # commonalities: system packages

      ./users/users.nix # commonalities
      ./users/cfo.nix # chief family officer group
      ./users/aeiuno/aeiuno.nix
      ./users/nicky/nicky.nix
    ];

  # Allow unfree packages
  nixpkgs.config.allowUnfree = true;
  home-manager.useGlobalPkgs = true; # with this, HomeManager will use the same pkgs config as nixos, amongst others the same value for config.allowUnfree


  # networking.wireless.enable = true;  # Enables wireless support via wpa_supplicant.

  # Configure network proxy if necessary
  # networking.proxy.default = "http://user:password@proxy:port/";
  # networking.proxy.noProxy = "127.0.0.1,localhost,internal.domain";

  # Set your time zone.
  #time.timeZone = "Europe/Brussels";

  # List packages installed in system profile. To search, run:
  # $ nix search wget
  environment.systemPackages = with pkgs; [
    micro #vim -> use neovim instead, with home manager # Do not forget to add an editor to edit configuration.nix! The Nano editor is also installed by default.
    wget
    bash
    kmod
    nixpkgs-fmt
    
    ### general purpose command-line tools
    binutils
    bottom
    cht-sh # command-line cheat sheet
    #fcp # Significantly faster alternative to the classic Unix cp(1) command
    fd # finder
    fzy # fuzzy finder
    hex # color hexdump
    inotify-tools # inotify-tools is a C library and a set of command-line programs for Linux providing a simple interface to inotify.  
    iw # Wireless interface config tool using nl80211.
    # ripgrep-all # ripgrep also file contents
    rm-improved
    unzip
    ###

    ### for hardware info
    clinfo
    dmidecode
    glxinfo
    pciutils
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
    libsForQt5.kig
    libsForQt5.kfind
    lightly-boehs # QT application theme
    mpv
    nixd # Nix language server
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
    (masterpdfeditor.overrideAttrs (old: rec {
      pname = "masterpdfeditor";
      version = "5.8.70";
      src = fetchurl {
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
    }))
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
    (pkgs.callPackage ./packages/applications/office/softmaker/softmaker_office.nix {
      officeVersion = {
        edition = "2024";
        version = "1222";
        hash = "sha256-E58yjlrFe9uFiWY0nXoncIxDgvwXD+REfmmdSZvgTTU=";
      };
    })
    vlc
    xdg-utils
    libmicrodns # for playing from VLC onto ChromeCast
    protobuf # for playing from VLC onto ChromeCast

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
    xorg.libxcb
    xorg.libX11
    xorg.libXext
    xorg.libXfixes
    xorg.libXrandr
    xorg.xcbutil
    xorg.xcbutilimage
    xorg.xcbutilkeysyms
    xorg.xcbutilrenderutil
    xorg.xcbutilwm
    libGL
    libGLU
    libxkbcommon
    patchelf
    ###
  ];


  # Some programs need SUID wrappers, can be configured further or are
  # started in user sessions.
  # programs.mtr.enable = true;
  # programs.gnupg.agent = {
  #   enable = true;
  #   enableSSHSupport = true;
  # };

  #nixpkgs.config.firefox.enablePlasmaBrowserIntegration = true; # enabled by default with Plasma
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
    ananicy = {
      # Rewrite of ananicy (Another auto nice daemon, with community rules support) in C++ for lower cpu and memory usage.
      enable = true;
      package = pkgs.ananicy-cpp;
    };

    openssh.enable = true; # Enable the OpenSSH daemon.
    syncthing.openDefaultPorts = true;
    tailscale.enable = true;
  };

  xdg.portal = {
    enable = true;
    #     extraPortals = [
    #       pkgs.xdg-desktop-portal-gtk
    #       pkgs.xdg-desktop-portal-wlr
    #     ];
    xdgOpenUsePortal = true;
  };
}
