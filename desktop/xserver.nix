# x11 role defines configuration for x11

{ config, lib, pkgs, ... }:

with lib;

{
  config = {
    programs = {
      dconf.enable = mkDefault true; # enable dconf support on all workstations for storage of configration
      # seahorse.enable = false;
      ssh.askPassword = lib.mkForce "${pkgs.kdePackages.ksshaskpass}/bin/ksshaskpass"; # resolves the conflict between seahorse (gnome) and ksshaskpass (plasma). Is just useful if both KDE and Gnome are installed.
    };
    services = {
      desktopManager={
        # plasma5 = { 
        #   enable = false; # Enable the KDE Plasma 5 Desktop Environment.
        # };
        plasma6 = {
          enable = true; # Enable the KDE Plasma 6 Desktop Environment.
          # Plasma's default UI font package is full noto-fonts, which brings
          # every script (Arabic, CJK, Indic, Thai, …). This system is used in
          # FR/DE/LU/NL/EN/PT only, so use the Latin/Greek/Cyrillic + symbol
          # subset instead. roles/fonts.nix already installs it as well; this
          # replaces the Plasma default rather than adding a second copy.
          notoPackage = pkgs.noto-fonts-lgc-plus;
        };
      };
      # GTK apps (Firefox, …) use gvfs for trash/MTP/network locations.
      # nixpkgs' Plasma module enables the udisks2 service itself, but not
      # gvfs, so the service is declared here (it was previously carried by
      # the now-removed desktop/hyprland.nix).
      gvfs.enable = true;
      displayManager = {
        defaultSession = "plasma";# = "gnome";
        sddm={
          autoNumlock = true;
          enable = true;
          # sddm.wayland is configured in desktop/plasma.nix to false for
          # NVIDIA open driver compatibility (kwin_wayland spins on open
          # NVIDIA KMS/drm-mode paths).
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
