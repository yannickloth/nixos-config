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
          wayland = {
            enable = true;
            compositor = "kwin";
          };
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
        adwaita-icon-theme # for apps like simple-scan
        caladea
        carlito
        charis-sil # Recommended by Matthew Butterick
        cooper-hewitt # Recommended by Matthew Butterick
        corefonts
        courier-prime
        dejavu_fonts
        dina-font
        encode-sans
        garamond-libre
        gelasio
        gentium #
        gentium-book-basic #
        gyre-fonts
        hasklig
        ibm-plex # Recommended by Matthew Butterick
        inconsolata-nerdfont
        intel-one-mono # Intel One Mono, an expressive monospaced font family that’s built with clarity, legibility, and the needs of developers in mind.
        inter
        iosevka
        iosevka-comfy.comfy
        liberation_ttf
        material-design-icons
        material-icons
        merriweather
        mplus-outline-fonts.githubRelease
        (nerdfonts.override { fonts = [ "FiraCode" "FiraMono" "DroidSansMono" "JetBrainsMono" "Noto" "ProFont" "RobotoMono" "Ubuntu" "UbuntuMono" "VictorMono" ]; })
        #noto-fonts-emoji
        office-code-pro # Customized version of Source Code Pro. The customizations were made specifically for text editors and coding environments.
        open-sans
        overpass # the open source typeface used by the Red Hat brand identity. 
        proggyfonts
        raleway
        redhat-official-fonts
        # roboto # no need for this, the inter font just looks better. https://mattwestcott.org/blog/an-ode-to-the-inter-typeface
        roboto-slab
        sn-pro # SN Pro Font Family (https://supernotes.app/open-source/sn-pro/). SN Pro is a friendly sans serif typeface optimized for use with Markdown.
        source-code-pro
        source-sans-pro
        terminus_font
        #twemoji-color-font
        #twitter-color-emoji
        #vistafonts
        # whatsapp-emoji-font
      ];
    };
  };
}
