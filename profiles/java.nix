{ config, lib, pkgs, ... }:

with lib;
{
  programs.java = {
    enable = true;
    package = pkgs.jdk22;
    binfmt = true;
  };
}
