{ config, lib, pkgs, ... }:

with lib;

{
  # Per-host build parallelism. Declare once per host instead of duplicating
  # the full nix.settings block:
  #   laptop-xps: 4  cores/8 threads, 16 GiB RAM  -> maxJobs = 4 (RAM-bound)
  #   laptop-hera: 64 GiB RAM                     -> maxJobs = 12, cores = 0
  #   laptop-p16:  128 GiB RAM                    -> maxJobs = 12, cores = 0
  options.roles.nix = {
    maxJobs = mkOption {
      type = types.int;
      default = 4;
      description = "Maximum number of parallel Nix jobs (nix.settings.max-jobs).";
    };
    cores = mkOption {
      type = types.nullOr types.int;
      default = null;
      description = "Concurrent tasks per build (nix.settings.cores). 0 = all cores; null = unset.";
    };
  };

  config = {
    environment.systemPackages = with pkgs; [
      cachix
    ];

    nix = {
      package = mkDefault pkgs.nixVersions.stable;
      settings = {
        # do builds in sandbox by default
        sandbox = mkDefault true;

        # per-host parallelism (declared via roles.nix.maxJobs/cores)
        max-jobs = mkDefault config.roles.nix.maxJobs;
        cores = mkIf (config.roles.nix.cores != null) (mkDefault config.roles.nix.cores);

        # system-features intentionally not set here: the nixpkgs default
        # already provides the full standard set (benchmark, cgroups, kvm,
        # nixos, nixos-test, reproducible-paths, sandbox, big-parallel).
        # Re-listing a subset would CONCATENATE with that default, producing
        # duplicates and failing to drop big-parallel. Leave it to the default.

        #         # set explicit binary cache and add additional binary caches
        substituters = [
          "https://attic.xuyh0120.win/lantian" # CachyOS kernel binary cache
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
        trusted-public-keys = [
          "hydra.nixos.org-1:CNHJZBh9K4tP3EKF6FkkgeVYsS3ohTl+oS0Qa8bezVs="
          "lantian:EeAUQ+W+6r7EtwnmYjeVwx5kOGEBpjlBfPlzGlTNvHc=" # CachyOS kernel binary cache
          #"xtruder-public.cachix.org-1:+qG/fM2195QJcE2BXmKC+sS4mX/lQHqwjBH83Rhzl14="
        ];
      };

      # enable nix command and flakes
      extraOptions = ''
        experimental-features = nix-command flakes
      '';
    };
  };
}
