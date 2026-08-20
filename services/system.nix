# System-wide services applied to all hosts.
# Split out of roles/system.nix (D-SERVICE vs D-SYSTEM driver separation).
# Imported by roles/system.nix.

{ config, pkgs, lib, ... }:

{
  services = {
    ananicy = {
      # Rewrite of ananicy (Another auto nice daemon, with community rules support) in C++ for lower cpu and memory usage.
      enable = true;
      package = pkgs.ananicy-cpp;
    };

    openssh.enable = true; # Enable the OpenSSH daemon.
    syncthing.openDefaultPorts = true;
    tailscale.enable = true;
  };
}
