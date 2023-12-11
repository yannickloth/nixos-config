{ config, lib, pkgs, ... }:

with lib;
{
  environment.systemPackages = with pkgs; [
    gnome.cheese
    gnome.gnome-themes-extra
    gnome.gpaste # Clipboard management system with GNOME 3 integration
    gnome.vinagre
    gnome.zenity
  ];
  services = {
    gnome = {
      at-spi2-core.enable = true; # A service for the Assistive Technologies available on the GNOME platform
      core-developer-tools.enable = true;
      core-os-services.enable = true;
      core-shell.enable = true;
      core-utilities.enable = true;
      games.enable = true;
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
  };
}
