# provides openssh defaults
{ config, lib, ... }:

with lib;

{
  config = {
    # enable openssh on server in vm
    services.openssh.enable = mkDefault true;

    # wlp58s0 is by default external interface
    networking.nat.externalInterface = mkDefault "wlp58s0";
    networking.firewall.allowedTCPPorts = [ 22 ];
  };
}
