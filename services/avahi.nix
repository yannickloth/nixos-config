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

  networking.firewall.extraInputRules = (import ../lib).privateNetRules {
    udp = [ "5353" ];
    v4 = (import ../lib).privateV4LinkLocal;
  };
}
