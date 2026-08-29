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
    ./laptop-xps.nix

    ../../roles/system.nix # common system packages and services

    ../../users/users.nix # commonalities
    ../../users/cfo.nix # chief family officer group
    ../../users/filedrop.nix # shared family drop folder
    ../../users/aeiuno/aeiuno.nix
    ../../users/nicky/nicky.nix
    ../../users/sven/sven.nix
    ../../users/aaron/aaron.nix
  ];

  # The Master PDF Editor is not installed on this host.
  system.masterPdfEditor.enable = false;

  # Host-specific packages on top of the shared set in roles/system.nix.
  environment.systemPackages = with pkgs; [
    nixfmt
  ];

  # NOTE: permittedInsecurePackages must live in roles/system.nix only;
  # definitions here would silently override it (see comment there).
}
