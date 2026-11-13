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
      uid = 1000; # explicit/stable (the Tor kid-block nftables rule keys on uid)
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
