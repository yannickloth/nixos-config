{ config, lib, pkgs, ... }:

with lib;
{
  programs.appimage = {
    binfmt = true;
    enable = true;
  };
}
