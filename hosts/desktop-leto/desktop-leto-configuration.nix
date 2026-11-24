# This value determines the NixOS release from which the default
# settings for stateful data, like file locations and database versions
# on your system were taken. It‘s perfectly fine and recommended to leave
# this value at the release version of the first install of this system.
# Before changing this value read the documentation for this option
# (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
{ config, pkgs, lib, ... }:

{
  system.stateVersion = "26.05"; # Did you read the comment?

  imports = [
    ./desktop-leto.nix

    ../../roles/system.nix # common system packages and services

    ../../users/users.nix # commonalities
    ../../users/cfo.nix # chief family officer group
    ../../users/filedrop.nix # shared family drop folder
    ../../users/aeiuno/aeiuno.nix
    ../../users/nicky/nicky.nix
    ../../users/sven/sven.nix
    ../../users/aaron/aaron.nix
  ];

  # Desktop/child gaming: install extra tools for the little ones (lutris,
  # game-specific emulators) on top of the shared family-gaming stack.
  environment.systemPackages = with pkgs; [
    lutris

    # Optical media — built-in HL-DT-ST DVDRAM GH24NSB0 DVD±RW.
    # k3b bundles its codec/burn deps (FLAC/MP3/OGG, cdrdao, dvdplusrwtools,
    # libburn, libdvdcss) in its own wrapper, so no separate "extras" package.
    kdePackages.k3b           # KDE disc burner (GUI)
    brasero                   # GNOME disc burner (kids also use it)
    dvdplusrwtools            # growisofs, dvd+rw-mediainfo (CLI DVD burning)
    cdrkit                    # genisoimage — create ISO images from directories
    handbrake                 # Rip DVD/Blu-ray to video (links libdvdcss itself)
  ];
}
