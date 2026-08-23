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
        # No explicit port ranges here: KDE Connect (1714-1764 TCP/UDP) is
        # opened automatically by programs.kdeconnect.enable only where it is
        # enabled (currently laptop-xps), and mDNS discovery (UDP 5353) by
        # services.avahi.openFirewall. SONOS opens its own ports.
      };
      # nix-serve (port 5000) is reachable only from Tailscale peers (CGNAT
      # 100.64.0.0/10) so the laptops can share builds; not from LAN/internet.
      firewall.extraInputRules = ''
        tcp dport 5000 ip saddr 100.64.0.0/10 accept
      '';
    };
}
