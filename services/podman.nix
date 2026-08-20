{ config, lib, pkgs, ... }:

with lib;
{
  virtualisation.podman = {
    enable=true;
    dockerCompat=true;
    dockerSocket.enable=true;
  };
  
  environment.systemPackages = with pkgs; [
     podman-compose # An implementation of docker-compose with podman backend.
     podman-desktop
     podman-tui
     pods
   ];
}
