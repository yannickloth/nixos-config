{ config, pkgs, ... }:
let
  username = "aaron";
  userDescription = "aaron";
in
{
  security.pam.services.aaron.logFailures = true;
  users = {
    groups.aaron = {
      name = username;
    };
    users.aaron = {
      isNormalUser = true; # Indicates whether this is an account for a "real" user. This automatically sets group to users, createHome to true, home to /home/«username», useDefaultShell to true, and isSystemUser to false. Exactly one of isNormalUser and isSystemUser must be true.
      uid = 1003; # explicit/stable (the Tor kid-block nftables rule keys on uid)
      description = userDescription;
      shell = pkgs.zsh;
      extraGroups = [ "users" ] ++ config.users.commonExtraGroups;
      group = username;
    };
  };
}
