
{ config, lib, pkgs, ... }:

with lib;
{
  services.kmscon = {
    enable = true; # Use kmscon as the virtual console instead of gettys.
    hwRender = true; # Whether to use 3D hardware acceleration to render the console.
    fonts = [
      { name = "FiraCode Nerd Font Mono"; package = pkgs.nerd-fonts.fira-code; }
      { name = "Inconsolata Nerd Font Mono"; package = pkgs.nerd-fonts.inconsolata; }
      { name = "Source Code Pro"; package = pkgs.source-code-pro; }
    ];
    extraConfig = "xkb-layout=be";
  };
}
