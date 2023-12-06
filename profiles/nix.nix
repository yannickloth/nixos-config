{ config, lib, pkgs, ... }:

with lib;

{
  config = {
    environment.systemPackages = with pkgs; [
      cachix
    ];

    nix = {
      package = mkDefault pkgs.nixFlakes;
      settings = {
        # do builds in sandbox by default
        sandbox = mkDefault true;

#         # set explicit binary cache and add additional binary caches
#         substituters = [
#           "https://cache.nixos.org/"
#           "https://xtruder-public.cachix.org"
#         ];
#         trusted-substituters = [
#           "https://cache.nixos.org/"
#           "https://xtruder-public.cachix.org"
#         ];
#         trusted-public-keys = [
#           "hydra.nixos.org-1:CNHJZBh9K4tP3EKF6FkkgeVYsS3ohTl+oS0Qa8bezVs="
#           "xtruder-public.cachix.org-1:+qG/fM2195QJcE2BXmKC+sS4mX/lQHqwjBH83Rhzl14="
#         ];
      };

      # enable nix command and flakes
      extraOptions = ''
        experimental-features = nix-command flakes
      '';
    };
  };
}
