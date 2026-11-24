# This value determines the NixOS release from which the default
# settings for stateful data, like file locations and database versions
# on your system were taken. It's perfectly fine and recommended to leave
# this value at the release version of the first install of this system.
# Before changing this value read the documentation for the option
# (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
{ ... }:

{
  system.stateVersion = "26.05"; # Did you read the comment?

  imports = [
    ./server-nike.nix

    ../../roles/system.nix # common system packages and services

    ../../users/users.nix # commonalities
    ../../users/cfo.nix # chief family officer group
    ../../users/filedrop.nix # shared family drop folder
    ../../users/aeiuno/aeiuno.nix
    ../../users/nicky/nicky.nix
    ../../users/sven/sven.nix
    ../../users/aaron/aaron.nix
  ];
}
