# x11 role defines configuration for x11

{ config, lib, pkgs, ... }:

with lib;

{
  config = {
    programs = {
      dconf.enable = mkDefault true; # enable dconf support on all workstations for storage of configration
      # seahorse.enable = false;
      ssh.askPassword = lib.mkForce "${pkgs.ksshaskpass}/bin/ksshaskpass"; # resolves the conflict between seahorse (gnome) and ksshaskpass (plasma). Is just useful if both KDE and Gnome are installed.
    };
    services = {
      desktopManager={
        plasma6.enable = true; # Enable the KDE Plasma 6 Desktop Environment.
      };
      displayManager = {
        defaultSession = "plasma";# = "gnome";
        sddm={
          autoNumlock = true;
          enable = true;
          wayland.enable = false;
        };
      };
      # gnome.gnome-keyring.enable = lib.mkForce false;
      
      # enable xserver on workstations
      xserver = {
        # By default, enable the X11 windowing system
        # enable = mkDefault true;
        enable = true;
        autorun = true;

        # Export configuration, so it's easier to debug
        exportConfiguration = true;

        # Configure keymap in X11
        xkb.layout = "be";
        xkb.variant = "";

        desktopManager = {
          gnome = {
            enable = false;
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
        };
      };
    };
    security = {
      pam.services.aeiuno.enableKwallet = true;
      pam.services.nicky.enableKwallet = true;
      #pam.services.aeiuno.enableGnomeKeyring = true;
      #pam.services.nicky.enableGnomeKeyring = true;
    };

    fonts = {
      enableDefaultPackages = true;
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
    };
  };
}
