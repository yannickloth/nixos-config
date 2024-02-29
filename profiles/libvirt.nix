{ config, lib, pkgs, ... }:

with lib;
{
  virtualisation = {
    libvirtd.enable = true;
    spiceUSBRedirection.enable = true;
    kvmgt = {
      enable = true;
    };
  };
  
}
