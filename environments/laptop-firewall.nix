{ config, lib, pkgs, ... }:

with lib;

{
    networking = {
      #nftables.enable = true;
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
