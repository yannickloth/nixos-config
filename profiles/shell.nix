{ config, lib, pkgs, ... }:

with lib;
{
  environment.systemPackages = with pkgs; [
    lsd
  ];
  environment.shellAliases = {
    ls = "lsd"; # replace ls by lsd
    ll = "ls -lha";
    l = "ls -l";
    la = "ls -a";
    lla = "ls -la";
    lt = "lsd --tree"; # --tree is not supported by 'ls', so in any case when ls is not aliased to lsd, 'lsd --tree' will continue to work
    ".." = "cd ..";
    nrs = "sudo nixos-rebuild switch";
    nrsu = "sudo nixos-rebuild switch --upgrade";
    myip = "curl ipinfo.io/ip"; # print public IPv4 address
  };
}
