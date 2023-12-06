{ config, lib, pkgs, ... }:

with lib;
{
  programs.xwayland = {
    enable = true;
  };
}
