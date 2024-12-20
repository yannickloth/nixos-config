{ config, pkgs, ... }:

{
  # Automatic Garbage Collection
  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 60d";
  };
}
