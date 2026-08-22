{ config, lib, pkgs, ... }:

let
  # Determine whether the host has at least 48 GiB of RAM at build time.
  # Nix builds run locally on the target during `nixos-rebuild`, so a
  # runCommand derivation can read the real /proc/meminfo. (Plain
  # builtins.readFile fails on procfs, hence the derivation.)
  memTotalKB =
    let
      meminfo = builtins.readFile (pkgs.runCommand "meminfo" { } ''
        grep MemTotal /proc/meminfo > "$out"
      '');
      captured = builtins.match "MemTotal: *([0-9]+) kB[[:space:]]*" meminfo;
    in
    builtins.fromJSON (builtins.elemAt captured 0);

  has48GB = memTotalKB >= 48 * 1024 * 1024;

  homeUsers = [ "nicky" "aeiuno" "sven" "aaron" ];
in
{
  # Enable psd (browser profiles in RAM) for every home-manager user only on
  # hosts with >= 48 GiB RAM; otherwise psd is not installed and browser
  # profiles remain on disk.
  config = lib.mkIf has48GB {
    home-manager.users = builtins.listToAttrs (
      map (user: {
        name = user;
        value.commonHm.enablePsd = true;
      }) homeUsers
    );
  };
}
