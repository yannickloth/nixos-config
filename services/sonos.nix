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
      #
      # Match semantics mirror the original iptables rules:
      #   OUTPUT: -j SET --add-set upnp src,src
      #   INPUT : -m set --match-set upnp dst,dst
      # i.e. the reply is accepted when its destination (ip . port) equals a
      # recorded outbound query source (ip . port).
      #
      # Why the set and chains live inside the nixos-fw table rather than a
      # dedicated table: nftables traverses EVERY base chain on a hook in
      # priority order, and an `accept` in one chain does not stop a later
      # chain from dropping the packet (nixos-fw input, priority filter, has
      # policy drop). The accept must therefore be the final verdict on the
      # input hook, i.e. happen inside nixos-fw's input-allow chain (via
      # extraInputRules). A rule can only reference sets in its own table, so
      # the upnp set and the output tracking chain must live in the nixos-fw
      # table too (merged in with mkBefore so the set is declared before use).
      nftables.tables."nixos-fw".content = mkBefore ''
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
      '';

      # Accept only replies matching a recorded query (short-lived): the reply
      # is unicast from the speaker to the client's ephemeral port, so match
      # (daddr . dport) against the recorded (saddr . sport). Runs at the end
      # of input-allow, i.e. after the allowedTCP/UDPPort checks have failed
      # for the ephemeral reply port and before the input chain's policy drop.
      firewall.extraInputRules = ''
        ip protocol udp ip daddr . udp dport @upnp accept
      '';
    };
  };
}
