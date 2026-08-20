{ config, lib, pkgs, ... }:

with lib;
{
  users.groups.steam = {
    members = [ "aeiuno" "nicky" "sven" ]; # Shared Steam library access
  };

  systemd.tmpfiles.rules = [
    "d /steamlib 2775 root steam -" # Shared Steam library, setgid so new files inherit the steam group
  ];

  programs.steam = {
    dedicatedServer.openFirewall = true; # Open ports in the firewall for Source Dedicated Server
    enable = true;
    localNetworkGameTransfers.openFirewall = true; # Open ports in the firewall for Steam Local Network Game Transfers.
    remotePlay.openFirewall = true; # Open ports in the firewall for Steam Remote Play
  };
}
