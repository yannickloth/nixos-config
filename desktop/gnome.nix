{ config, lib, pkgs, ... }:

with lib;
{
 
  xdg.mime.defaultApplications = {
    # Replace Nautilus with Nemo as the default file manager
    "application/x-gnome-saved-search" = [
      "nemo.desktop"
    ];
    
    # Replace Nautilus with Nemo as the default file manager
    "inode/directory" = [
      "nemo.desktop"
    ];
  };
 
  environment.systemPackages = with pkgs; [
    cinnamon.nemo-with-extensions
    flat-remix-gnome
    flat-remix-gtk
    flat-remix-icon-theme 
    gnome.cheese
    gnome.gnome-themes-extra
    gnome.gpaste # Clipboard management system with GNOME 3 integration
    gnome.vinagre
    gnome.zenity
    gnomeExtensions.prime-gpu-profile-selector
    layan-gtk-theme
    orchis-theme
    sysprof # Install sysprof
    yaru-theme
    yaru-remix-theme
  ];
  services = {
    gnome = {
      at-spi2-core.enable = true; # A service for the Assistive Technologies available on the GNOME platform
      core-developer-tools.enable = true;
      core-os-services.enable = true;
      core-shell.enable = true;
      core-utilities.enable = true;
      games.enable = true;
      glib-networking.enable = true;
      gnome-browser-connector.enable = true;
      gnome-initial-setup.enable = true;
      gnome-online-accounts.enable = true;
      gnome-online-miners.enable = true;
      gnome-remote-desktop.enable = true;
      gnome-settings-daemon.enable = true;
      rygel.enable = true;
      sushi.enable = true;
      tracker = {
        enable = true;
      };
      tracker-miners.enable = true;
      gnome-user-share.enable = true;
    };
    sysprof.enable = true; # Enable sysprof
  };
}
