{ config, lib, ... }:

with lib;

{
  config = {
    networking = {
      # enable networkmanager on all workstations and use local dnsmasq server
      networkmanager = {
        enable = true;

        # always use local dnsmasq for dns server
        #insertNameservers = ["127.0.0.1"];
      };
      # enable resolvconf
      resolvconf.enable = true;

      # disable wpasupplicant, as networkmanager manages wireless
      wireless.enable = false;
    };

    # enable dnsmasq for dns caching server
    services.dnsmasq = {
      #enable = mkDefault true;
      enable = false;

      # additional secure configuration for dnsmasq
#       extraConfig = ''
#         strict-order # obey strict order of dns servers
#       '';
      settings = {
        server = [
          "192.168.190.79"
          "192.168.190.1"
          "9.9.9.9"
          "1.1.1.1"
        ];
        strict-order = true; # obey strict order of dns servers
      };
    };    
  };
}
