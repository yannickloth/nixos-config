{ config, lib, pkgs, ... }:

with lib;
{
  services.flatpak.enable = true;
}
