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
      description = userDescription;
      shell = pkgs.zsh;
      extraGroups = [ "users" "wheel" ] ++ config.users.commonExtraGroups;

      group = username;
    };
  };
}
