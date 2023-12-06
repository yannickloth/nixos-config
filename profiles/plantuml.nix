
{ config, lib, pkgs, ... }:

with lib;
{
  services.plantuml-server = {
    enable = true;
    #allowPlantumlInclude = true;
    listenPort = 10101;
  };
  environment.systemPackages = with pkgs; [
    graphviz
  ];
}
