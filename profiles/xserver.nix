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
        # plasma5 = { 
        #   enable = false; # Enable the KDE Plasma 5 Desktop Environment.
        # };
        plasma6 = {
          enable = true; # Enable the KDE Plasma 6 Desktop Environment.
        };
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
        xkb = {
          layout = "be";
          variant = "";
        };
      };
    };
    security = {
      pam.services.aeiuno.enableKwallet = true;
      pam.services.nicky.enableKwallet = true;
      #pam.services.aeiuno.enableGnomeKeyring = true;
      #pam.services.nicky.enableGnomeKeyring = true;
    };
  };
}
