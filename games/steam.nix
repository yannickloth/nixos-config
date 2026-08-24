{ config, lib, pkgs, ... }:

with lib;
{
  users.groups.steam = {
    members = [ "aeiuno" "nicky" "sven" "aaron" ]; # Shared Steam library access
  };

  systemd.tmpfiles.rules = [
    # Shared Steam library, setgid so new files inherit the steam group.
    "d /steamlib 2775 root steam -"
    # Access + default ACL: umask 022 would otherwise give group members only
    # r-x on newly created dirs, blocking writes by other family members.
    "A /steamlib 2775 root steam - u::rwx,g::rwx,o::rx"
    # Recursively heal owner/mode/setgid of existing content on every boot.
    "Z /steamlib 2775 root steam -"
  ];

  programs.steam = {
    dedicatedServer.openFirewall = true; # Open ports in the firewall for Source Dedicated Server
    enable = true;
    localNetworkGameTransfers.openFirewall = true; # Open ports in the firewall for Steam Local Network Game Transfers.
    remotePlay.openFirewall = true; # Open ports in the firewall for Steam Remote Play
  };
}
