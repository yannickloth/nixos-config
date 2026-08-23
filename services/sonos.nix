{ config, lib, pkgs, ... }:
with lib;
{
  config = {
    networking = {
      firewall = {
        # Open ports in the firewall.
        allowedTCPPorts = [
          445 # SONOS
          1400 # SONOS
          3445 # SONOS
          3400 # SONOS
          3401 # SONOS
          3500 # SONOS
          4444 # SONOS
        ];
        allowedTCPPortRanges = [
          { from = 1400; to = 1499; } # SONOS
        ];
        allowedUDPPorts = [
          1900 # SONOS
          1901 # SONOS
          6969 # SONOS
        ];
      };

      # nftables backend must be enabled for the SSDP rule below
      # (set via environments/laptop-firewall.nix -> networking.nftables.enable).
      # SONOS SSDP (UPnP) discovery: the client sends an M-SEARCH to the
      # multicast address 239.255.255.250:1900 and speakers reply with a short
      # unicast UDP packet to the client's ephemeral source port. This is a NEW
      # inbound flow, so `ct state established` will not match it.
      #
      # nftables replacement for the old ipset/iptables hack (ipset "upnp"
      # hash:ip,port with a 3s timeout): track the outbound query's
      # (source-ip . source-port) and accept only matching replies. nftables
      # has native sets with timeouts, so no external ipset is needed.
      nftables.tables.sonos-ssdp = {
        family = "inet";
        content = ''
          set upnp {
            type ipv4_addr . inet_service
            flags timeout
            timeout 3s
          }
          chain output {
            type filter hook output priority 110; policy accept;
            # record each outbound SSDP query source (ip . sport)
            ip protocol udp udp dport 1900 ip daddr 239.255.255.250 \
              add @upnp { ip saddr . udp sport timeout 3s }
          }
          chain input {
            type filter hook input priority 0; policy accept;
            # accept only replies matching a recorded query (short-lived)
            ip protocol udp udp dport 1900 @upnp { ip saddr . udp sport } accept
          }
        '';
      };
    };
  };
}
