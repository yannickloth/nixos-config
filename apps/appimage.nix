{ lib, ... }:

with lib;
{
  programs.appimage = {
    binfmt = true;
    enable = true;
  };
}
