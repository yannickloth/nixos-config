{ config, lib, pkgs, ... }:

with lib;
{
  hardware.ckb-next = {
    enable = true;
  };

#   environment.systemPackages = with pkgs; [
#     ckb-next # Driver and configuration tool for Corsair keyboards and mice
#   ];
}
