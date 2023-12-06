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
        
        # support SSDP https://serverfault.com/a/911286/9166
        extraPackages = [ pkgs.ipset ];
        extraCommands = ''
          if ! ipset --quiet list upnp; then
            ipset create upnp hash:ip,port timeout 3
          fi
          iptables -A OUTPUT -d 239.255.255.250/32 -p udp -m udp --dport 1900 -j SET --add-set upnp src,src --exist
          iptables -A nixos-fw -p udp -m set --match-set upnp dst,dst -j nixos-fw-accept
        '';
       
# With recent Linux kernels (>= 2.6.39) you can use kernel's ipset to workaround limitation of connection tracking. You do not need to write any userspace or kernel helper. For UPnP SSDP it can be written as:
# 
# First command creates a new ipset called upnp which stores tuple (ip address, ip protocol, ip port) and every inserted record expires in 3 seconds.
# 
# Second command matches outgoing UPnP SSDP packet (destination is multicast address 239.255.255.250 on udp port 1900) and stores source ip address and source udp port of packet into ipset upnp. First keyword src means source ip address and second keyword src means source port as ipset of type hash:ip,port always needs such pair. Keyword --exists means that for existing record is timer reseted. This stored record is automatically removed in 3 seconds.
# 
# Third command matches incoming udp packet and if its destination address and destination port matches some record in ipset upnp then this packet is accepted. Syntax dst,dst means destination ip address and destination port.
# 
# UPnP clients normally sends udp packet to 239.255.255.250:1090 and wait just 2 seconds for response. So autoexpiration in 3 seconds in ipset is enough.
# 
# I have not found on internet any working firewall/iptables configuration for UPnP clients which is not too relax (e.g. accept all incoming UDP packet) or without some userspace tracking or need to patch kernel.

      };
    };
  };
}
