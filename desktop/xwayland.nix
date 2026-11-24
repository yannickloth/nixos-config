{ lib, ... }:

with lib;
{
  programs.xwayland = {
    enable = true;
  };
}
