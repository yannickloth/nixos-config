{ config, pkgs, ... }:
let
  username = "aeiuno";
  userDescription = "aeiuno";
in
{
  security.pam.services.aeiuno.logFailures = true;
  users = {
    groups.aeiuno = {
      name = username;
    };
    users.aeiuno = {
      isNormalUser = true; # isNormalUser = true; # Indicates whether this is an account for a “real” user. This automatically sets group to users, createHome to true, home to /home/«username», useDefaultShell to true, and isSystemUser to false. Exactly one of isNormalUser and isSystemUser must be true.
      # Fleet convention: hosts installed from scratch have aeiuno=1001,
      # nicky=1000. laptop-hera predates that layout (aeiuno was created first
      # there, so it is 1000) and NixOS never changes an existing user's uid;
      # that host overrides this with mkForce (hosts/laptop-hera/laptop-hera.nix).
      uid = 1001; # explicit/stable
      description = userDescription;
      shell = pkgs.zsh;
      extraGroups = [ "users" "wheel" ] ++ config.users.commonExtraGroups;
      group = username;
      # Family SSH identity (public half); the private half is installed by
      # services/ssh-user-keys.nix. Kept here (not in that module) because
      # defining users.users while probing config.users.users recurses.
      openssh.authorizedKeys.keys = [ (import ../ssh-public-keys.nix).aeiuno ];
    };
  };
}
