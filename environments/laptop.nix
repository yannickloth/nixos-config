# laptop role is used on all portable laptop machines

{ config, lib, pkgs, ... }:

with lib;

{
  imports =
  [
    ../profiles/laptop-firewall.nix
  ];
  config = {


    # enable suspend
    powerManagement.enable = mkDefault true;

    # for power optimizations
    powerManagement.powertop.enable = true;

    #services.low-battery-check = {
      #enable = true;
      #action = "hibernate";
    #};

    # Gnome 40 introduced a new way of managing power, without tlp.
    # However, these 2 services clash when enabled simultaneously.
    # https://github.com/NixOS/nixos-hardware/issues/260
    services.tlp.enable = lib.mkDefault ((lib.versionOlder (lib.versions.majorMinor lib.version) "21.05")
                                       || !config.services.power-profiles-daemon.enable);

    # enable upower service for battery
    #services.upower = {
    #  enable = false; # Whether to enable Upower, a DBus service that provides power management support to applications.
    #  criticalPowerAction = "Hibernate";
    #};

    # Do not turn off when closing laptop lid
    services.logind.extraConfig = ''
      HandleLidSwitch=ignore
    '';

    # keep timezone updated to local time using geoclue
    time.timeZone = lib.mkForce "Europe/Luxembourg"; # force because somewhere else this is set to null, and Nix does not know how to resolve the conflict
    services.localtimed.enable = true;

    # enable captive-browser, so we can connect to network that are secured
    # by captive portal
    programs.captive-browser.enable = true;
    programs.captive-browser.interface = "wlp58s0";
  };
}
