{ config, lib, pkgs, ... }:

with lib;
{
  environment.systemPackages = with pkgs; [
    # conda # Conda is a package manager for Python
    # python311Packages.ipykernel
    uv
  ];
}
