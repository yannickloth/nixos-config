{ config, lib, ... }:

with lib;

{
  config = {
    networking = {
      # enable networkmanager on all workstations and use local dnsmasq server
      networkmanager = {
        enable = true;

        # always use local dnsmasq for dns server
        insertNameservers = ["127.0.0.1"];
      };
      # enable resolvconf
      resolvconf.enable = true;

      # disable wpasupplicant, as networkmanager manages wireless
      wireless.enable = false;
    };

    # enable dnsmasq for dns caching server
    services.dnsmasq = {
      enable = mkDefault true;

      # additional secure configuration for dnsmasq
#       extraConfig = ''
#         strict-order # obey strict order of dns servers
#       '';
      settings = {
        strict-order = true; # obey strict order of dns servers
      };
    };    
  };
}
