{ config, pkgs, ... }:
let
  username = "nicky";
  userDescription = "nicky";
in
{
  security.pam.services.nicky.logFailures = true;
  users = {
    groups.nicky = {
      name = username;
    };
    users.nicky = {
      isNormalUser = true; # Indicates whether this is an account for a "real" user. This automatically sets group to users, createHome to true, home to /home/«username», useDefaultShell to true, and isSystemUser to false. Exactly one of isNormalUser and isSystemUser must be true.
      # Fleet convention: nicky=1000, aeiuno=1001 (the reverse of laptop-hera,
      # which overrides both with mkForce; see users/aeiuno/aeiuno.nix). The
      # Tor kid-block keys on sven/aaron, not on this uid.
      uid = 1000; # explicit/stable
      description = userDescription;
      shell = pkgs.zsh;
      extraGroups = [ "users" "wheel" ] ++ config.users.commonExtraGroups;

      group = username;
      # Family SSH identity (public half); the private half is installed by
      # services/ssh-user-keys.nix. Kept here (not in that module) because
      # defining users.users while probing config.users.users recurses.
      openssh.authorizedKeys.keys = [ (import ../ssh-public-keys.nix).nicky ];
    };
  };
}
