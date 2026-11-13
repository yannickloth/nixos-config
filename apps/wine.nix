{ config, lib, pkgs,... }:

with lib;

{
  environment.systemPackages = with pkgs; [
    # wineWow64 (not the deprecated wineWow): a native 64-bit wine that runs
    # 32- and 64-bit Windows apps. The legacy wineWow build (32-bit stdenv +
    # builder-wow.sh) is not in the nixos-26.05 Hydra jobset, so it always
    # compiles from source; wineWow64Packages.stable is in cache.nixos.org.
    wineWow64Packages.stable
    winetricks
  ];
}


