{ config, lib, pkgs, ... }:

with lib;
{
  programs.java.enable = true;
  programs.java.package = pkgs.jdk21;
}
