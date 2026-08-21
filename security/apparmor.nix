{ config, lib, pkgs, ... }:

with lib;
{
  config = {
    security.apparmor = {
      enable = mkDefault true;
      enableCache = mkDefault true;
    };
  };
}
