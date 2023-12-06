{ config, lib, pkgs, ... }:

with lib;
{
  programs.k3b.enable = true;
  environment.systemPackages = with pkgs; [
    cdrdao
    cdrkit
    libdvdcss
    #libsForQt5.k3b
  ];
}
