# x11 role defines configuration for x11

{ config, lib, pkgs, ... }:

with lib;

{
  config = {
    programs.ssh.askPassword = lib.mkForce "${pkgs.ksshaskpass}/bin/ksshaskpass"; # resolves the conflict between seahorse (gnome) and ksshaskpass (plasma). Is just useful if both KDE and Gnome are installed.
    services.desktopManager.plasma6.enable = true; # Enable the KDE Plasma 6 Desktop Environment.
    # enable xserver on workstations
    services.xserver = {
      # By default, enable the X11 windowing system
      #enable = mkDefault true;
      enable = true;
      autorun = true;

      # Export configuration, so it's easier to debug
      exportConfiguration = true;

      # Configure keymap in X11
      xkb.layout = "be";
      xkb.variant = "";

      desktopManager = {
       gnome = {
          enable = true;
        };
        # Enable the KDE Plasma Desktop Environment.
        # plasma5 = {
        #   enable = false;
        # };
        xterm.enable = false;
      };
      displayManager = {
        gdm = {
          enable = false;
        };
        sddm = {
          autoNumlock = true;
          enable = true;
          wayland.enable = false;
        };
        defaultSession = "plasma";# = "gnome";
      };
    };
    services.gnome.gnome-keyring.enable = lib.mkForce false;
    programs.seahorse.enable = false;
    security = {
      pam.services.aeiuno.enableKwallet = true;
      pam.services.nicky.enableKwallet = true;
      #pam.services.aeiuno.enableGnomeKeyring = true;
      #pam.services.nicky.enableGnomeKeyring = true;
    };
    fonts = {
      packages = with pkgs; [
        caladea
        carlito
        corefonts
        courier-prime
        dejavu_fonts
        dina-font
        encode-sans
        garamond-libre
        gelasio
        gyre-fonts
        hasklig
        inconsolata-nerdfont
        iosevka
        iosevka-comfy.comfy
        liberation_ttf
        material-design-icons
        material-icons
        merriweather
        mplus-outline-fonts.githubRelease
        (nerdfonts.override { fonts = [ "FiraCode" "FiraMono" "DroidSansMono" "JetBrainsMono" "Noto" "ProFont" "RobotoMono" "Ubuntu" "UbuntuMono" "VictorMono" ]; })
        noto-fonts-emoji
        open-sans
        overpass
        proggyfonts
        raleway
        roboto
        roboto-slab
        source-code-pro
        source-sans-pro
        terminus_font
        twemoji-color-font
        twitter-color-emoji
        vistafonts
        # whatsapp-emoji-font
      ];
      fontconfig = {
        enable = mkForce true;
        defaultFonts = {
          monospace = ["Roboto Mono 13"];
          sansSerif = ["Roboto 13"];
          serif = ["Roboto Slab 13"];
        };
      };
      fontDir = {
        enable = true;
      };
      enableDefaultPackages = true;
    };

    # enable dconf support on all workstations for storage of configration
    programs.dconf.enable = mkDefault true;

    # Enable touchpad support (enabled default in most desktopManager).
      services.xserver.libinput.enable = lib.mkDefault true;
    };
}
