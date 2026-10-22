{ config, lib, pkgs, ... }:

with lib;
{
  # mDNS is LAN-local, but `openFirewall` accepts UDP/5353 from every network
  # the laptop joins (hotel Wi-Fi included). Accept it from private ranges
  # only; requires the nftables backend (environments/laptop-firewall.nix).
  assertions = [
    {
      assertion = config.networking.nftables.enable;
      message = "services/avahi.nix: the scoped mDNS rule requires networking.nftables.enable";
    }
  ];

  services.avahi = {
    enable = true;
    # Important to resolve .local domains of printers, otherwise you get an error
    # like  "Impossible to connect to XXX.local: Name or service not known"
    nssmdns4 = true;
    openFirewall = false;
    browseDomains = [ "fritz.box" "local" "home" ];
  };

  networking.firewall.extraInputRules = ''
    ip saddr { 192.168.0.0/16, 10.0.0.0/8, 172.16.0.0/12, 100.64.0.0/10, 169.254.0.0/16 } udp dport 5353 accept
    ip6 saddr { fe80::/10, fc00::/7 } udp dport 5353 accept
  '';
}
