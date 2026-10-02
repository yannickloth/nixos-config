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

    # OpenSSH is configured (and firewall-opened) by services/openssh.nix,
    # which every host imports via environments/family-laptop.nix.
    tailscale.enable = true;
  };
}
