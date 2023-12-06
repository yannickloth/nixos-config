{ config, lib, pkgs, modulesPath, ... }:

{
  services.hardware.bolt.enable = true; # Whether to enable Bolt, a userspace daemon to enable security levels for Thunderbolt 3 on GNU/Linux.
}
 
