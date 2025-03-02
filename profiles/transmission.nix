{
  config,
  lib,
  pkgs,
  ...
}:

with lib;
{
  services = {
    transmission = {
      enable = true;
      group="cfo";
      openFirewall=true;
      openPeerPorts = true;
      openRPCPort = true; # Open firewall for RPC
      package = pkgs.transmission_4-qt6;
      user="aeiuno";
    };
  };
}
