{ config, pkgs, ... }:
let 
  username="aeiuno";
  userDescription="Christine Andres";
in
{
  users = {
    groups.aeiuno = {
      name = username;
    };
    users.aeiuno = {
      createHome = true;
      hashedPassword = "$2b$05$YGHKsI8io3H9wIbbN8KwAOX5woC8hZItpSAmLLcxG0sPdO6akjht2";
      isNormalUser = true;
      description = userDescription;
      extraGroups = [ "libvirtd" "lp" "networkmanager" "scanner" "vboxusers" "wheel" "yubikey" ];
      group = username;
    };
  };  
}
