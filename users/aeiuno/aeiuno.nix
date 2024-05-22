{ config, pkgs, ... }:
let 
  username="aeiuno";
  userDescription="aeiuno";
in
{
  security.pam.services.aeiuno.logFailures = true;
  users = {
    groups.aeiuno = {
      name = username;
    };
    users.aeiuno = {
      createHome = true;
      hashedPassword = "$2b$05$YGHKsI8io3H9wIbbN8KwAOX5woC8hZItpSAmLLcxG0sPdO6akjht2";
      isNormalUser = true;
      description = userDescription;
      extraGroups = [ "gamemode" # for gamemode CPU governor setting
                      "libvirtd"
                      "lp" # for scanning
                      "networkmanager"
                      "scanner" # for scanning
                      "vboxusers"
                      "wheel"
                      "yubikey" ];
      group = username;
    };
  };  
}
