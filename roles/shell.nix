{ config, lib, pkgs, ... }:

with lib;
{
  environment.systemPackages = with pkgs; [
    lsd
    zsh
  ];
  # Add zsh to the list of valid login shells (chsh-compatible). The login
  # shell itself is set per-user in users/<user>.nix (`shell = pkgs.zsh`).
  environment.shells = [ pkgs.zsh ];
  # Enable zsh at the system level so the login shells get the nix directories
  # in PATH (the NixOS shell-program check requires this).
  programs.zsh.enable = true;
  environment.shellAliases = {
    ls = "lsd"; # replace ls by lsd
    ll = "lsd -lha";
    l = "lsd -l";
    la = "lsd -a";
    lla = "lsd -la";
    lt = "lsd --tree"; # --tree is not supported by 'ls', so in any case when ls is not aliased to lsd, 'lsd --tree' will continue to work
    ".." = "cd ..";
    nrs = "sudo nixos-rebuild switch --flake ./";
    nrsu = "nix flake update && sudo nixos-rebuild switch --flake ./";
    nrsfh = "sudo nixos-rebuild switch --flake ./";
    myip = "${pkgs.curl}/bin/curl ipinfo.io/ip"; # print public IPv4 address
  };
}
