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
      description = userDescription;
      shell = pkgs.zsh;
      extraGroups = [ "users" "wheel" ] ++ config.users.commonExtraGroups;
      group = username;
    };
  };
}
