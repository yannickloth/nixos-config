{ config, lib, pkgs, ... }:

with lib;

{
  config = {
    environment.systemPackages = with pkgs; [
      cachix
    ];

    nix = {
      package = mkDefault pkgs.nixVersions.stable;
      settings = {
        # do builds in sandbox by default
        sandbox = mkDefault true;

#         # set explicit binary cache and add additional binary caches
          substituters = [
            "https://cache.nixos.org/"
            #"https://xtruder-public.cachix.org"
          ]
          #++ (if (config.networking.hostName != "laptop-xps") then [ "http://laptop-xps.bee-blues.ts.net:5000/" ] else []) # any other hosts should use laptop-xps as a nix store cache
          #++ (if (config.networking.hostName != "laptop-hera") then [ "http://laptop-hera.bee-blues.ts.net:5000/" ] else []) # any other hosts should use laptop-hera as a nix store cache
          #++ (if (config.networking.hostName != "laptop-p16") then [ "http://laptop-p16.bee-blues.ts.net:5000/" ] else []) # any other hosts should use laptop-p16 as a nix store cache
          ;
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
