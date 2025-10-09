{ config, lib, pkgs, ... }:

with lib;
{
  # List packages installed in system profile. To search, run:
  # $ nix search wget
  environment.systemPackages = with pkgs; [
    kcalc
    # latte-dock # Dock-style app launcher based on Plasma frameworks.
    kdePackages.plasma-browser-integration # TODO manually: copy org.kde.plasma.browser_integration.json from the derivation in the Nix Store into "~/.mozilla/native-messaging-hosts/", then make it R/W, then set the path to "/run/current-system/sw/bin/plasma-browser-integration-host"
    plasma5Packages.plasma-thunderbolt
    plasma-panel-colorizer # Fully-featured widget to bring Latte-Dock and WM status bar customization features to the default KDE Plasma panel.
  ];
}
