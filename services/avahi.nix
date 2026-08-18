{ config, lib, pkgs, ... }:

with lib;
{
  services.avahi = {
    enable = true;
    # Important to resolve .local domains of printers, otherwise you get an error
    # like  "Impossible to connect to XXX.local: Name or service not known"
    nssmdns4 = true;
    openFirewall = true;
    browseDomains = [ "fritz.box" "local" "home" ];
  };
}
