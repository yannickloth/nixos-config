{ config, lib, pkgs, ... }:

with lib;
{
  programs.steam = {
    dedicatedServer.openFirewall = true; # Open ports in the firewall for Source Dedicated Server
    enable = true;
    localNetworkGameTransfers.openFirewall = true; # Open ports in the firewall for Steam Local Network Game Transfers.
    remotePlay.openFirewall = true; # Open ports in the firewall for Steam Remote Play
  };
}
