{ config, lib, pkgs, ... }:

with lib;

{
    networking = {
      # nftables backend for the firewall. Requires that no iptables-based
      # `networking.firewall.extraCommands` remain: SONOS (services/sonos.nix)
      # was converted to a native nftables set and Samba's netbios-ns helper
      # (services/samba.nix) removed, so nftables now evaluates cleanly.
      nftables.enable = true;
      firewall = {
        enable = true;
        # Open ports in the firewall.
        allowedTCPPortRanges = [
          { from = 1714; to = 1764; } # kdeconnect
        ];

        allowedUDPPortRanges = [
          { from = 1714; to = 1764; } # kdeconnect
        ];
      };
    };
}
