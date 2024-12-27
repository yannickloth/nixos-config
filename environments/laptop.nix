# laptop role is used on all portable laptop machines

{ config, lib, pkgs, ... }:

with lib;

{
  imports =
    [
      ../profiles/laptop-firewall.nix
    ];
  config = {

    powerManagement = {
      enable = mkDefault true; # enable suspend
      powertop.enable = true; # Whether to enable powertop auto tuning on startup. Analyze power consumption on Intel-based laptops.
    };

    # As we always use laptops with Plasma or Gnome, just rely on their standard power management features. It's not as if we extensively used laptops without graphical interface.
    #services.tlp = {
      # Gnome 40 introduced a new way of managing power, without tlp.
      # However, these 2 services clash when enabled simultaneously.
      # https://github.com/NixOS/nixos-hardware/issues/260
      # enable = lib.mkDefault ((lib.versionOlder (lib.versions.majorMinor lib.version) "21.05") || !config.services.power-profiles-daemon.enable); # Disabled. Enable this to keep TLP (absolutely needed for TTY-only sessions, where no Plasma session is running in parallel) and let it manage CPU freq, and let Plasma's PowerDevil just manage display, not the CPU.
    #};

    # enable upower service for battery
    services.upower = {
      enable = true; # Enables battery monitoring daemon. Whether to enable Upower, a DBus service that provides power management support to applications.
      #criticalPowerAction = "Hibernate"; #The action to take when timeAction or percentageAction has been reached for the batteries (UPS or laptop batteries) supplying the computer
    };

    # Do not turn off when closing laptop lid
    services.logind.extraConfig = ''
      HandleLidSwitch=ignore
    '';

    # keep timezone updated to local time using geoclue
    time.timeZone = lib.mkForce "Europe/Luxembourg"; # force because somewhere else this is set to null, and Nix does not know how to resolve the conflict
    services.localtimed.enable = true;
  };
}
