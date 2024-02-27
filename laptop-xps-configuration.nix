# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running ‘nixos-help’).

{ config, pkgs, lib,... }:

{
  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It‘s perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = "23.05"; # Did you read the comment?
  
  imports =
    [ # Include the results of the hardware scan.
      #<nixpkgs/nixos/modules/services/hardware/sane_extra_backends/brscan4.nix>
      #<home-manager/nixos>

      ./hosts/laptop-xps/laptop-xps.nix
      
      ./modules/systemPackages.nix # commonalities: system packages
      
      ./users/users.nix # commonalities
      ./users/cfo.nix # chief family officer group
      ./users/aeiuno/aeiuno.nix
      ./users/nicky/nicky.nix
    ];

  # Allow unfree packages
  nixpkgs.config.allowUnfree = true;
  home-manager.useGlobalPkgs = true; # with this, HomeManager will use the same pkgs config as nixos, amongst others the same value for config.allowUnfree


  environment.sessionVariables.NIXOS_OZONE_WL = "1";
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

    ### general purpose command-line tools
    binutils
    bottom
    cht-sh # command-line cheat sheet
    fcp
    fd # finder
    fzy # fuzzy finder
    hex # color hexdump
    inotify-tools # inotify-tools is a C library and a set of command-line programs for Linux providing a simple interface to inotify.  
    # ripgrep-all # ripgrep also file contents
    rm-improved
    unzip
    ###

    ### for hardware info
    clinfo
    glxinfo
    pciutils
    vulkan-tools
    wayland-utils
    ###

    brave
    clamtk
    cryptomator # Free client-side encryption for your cloud files
    direnv # for lorri
    nix-direnv # for direnv
    distrobox
    eid-mw
    fuse3
    fuseiso
    #geogebra
    geogebra6
    gitFull
    gnome.simple-scan
    gnome.gnome-tweaks
    gparted
    htop
    killall
    libsForQt5.kig
    libsForQt5.kfind
    lightly-boehs # QT application theme
    p7zip # A new p7zip fork with additional codecs and improvements
    peazip # Cross-platform file and archive manager
    ocrmypdf
    qpwgraph # PipeWire graph manager
    shutter # Screenshot and annotation tool
    usbutils
    virt-manager
    virtiofsd
    (masterpdfeditor.overrideAttrs (old: rec {
      pname = "masterpdfeditor-${version}";
      version = "5.8.70";
      src = fetchurl {
        url = "https://code-industry.net/public/master-pdf-editor-${version}-qt5.x86_64.tar.gz";
        sha256 = "sha256-mheHvHU7Z1jUxFWEEfXv2kVO51t/edTK3xV82iteUXM=";
      };
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
    (pkgs.callPackage ./packages/applications/office/softmaker/softmaker_office.nix { officeVersion = {
        edition = "2024";
        version = "1208";
        hash = "sha256-qe5I2fGjpANVqd5KIDIUGzqFVgv+3gBoY7ndp0ByvPs=";
        }; })
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

  security = {
    sudo.wheelNeedsPassword = false;
  };
  #programs.firefox.enable=true;
  #programs.firefox.package=pkgs.librewolf;
  nixpkgs.config.firefox.enablePlasmaBrowserIntegration = true; # enabled by default with Plasma
  environment.sessionVariables = {
    MOZ_USE_XINPUT2 = "1"; # Makes Firefox use xinput2. This improves touchscreen support, enables additional touchpad gestures and enables smooth scrolling as opposed to the stepped scrolling that Firefox has by default.
  };

  programs = {
    bash = {
      enableCompletion=true;
#      interactiveShellInit= ''
#        eval "$(direnv hook bash)"
#      '';
    };
    command-not-found.enable = true; # Whether interactive shells should show which Nix package (if any) provides a missing command.
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
    ananicy = { # Rewrite of ananicy (Another auto nice daemon, with community rules support) in C++ for lower cpu and memory usage.
      enable = true;
	    package = pkgs.ananicy-cpp;
    };
    
    # Enable the OpenSSH daemon.
    openssh.enable = true;
    syncthing.openDefaultPorts=true;
    tailscale.enable = true;
  };

  xdg.portal = {
    enable = true; # Whether to enable xdg desktop integration.
    
#     extraPortals = [
#       pkgs.xdg-desktop-portal-gtk
#        pkgs.xdg-desktop-portal-wlr
#     ];
    xdgOpenUsePortal = true; # Sets environment variable NIXOS_XDG_OPEN_USE_PORTAL to 1 This will make xdg-open use the portal to open programs, which resolves bugs involving programs opening inside FHS envs or with unexpected env vars set from wrappers. See #160923 for more info.
  };

  

  

}
