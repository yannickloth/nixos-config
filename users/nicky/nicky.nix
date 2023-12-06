{ config, pkgs, ... }:
let 
  username="nicky";
  userDescription="Yannick Loth";
in
{
  users = {
    groups.nicky = {
      name = username;
    };
    users.nicky = {
      createHome = true;
      hashedPassword = "$2b$05$.x8gLS6s8Vd2qFsPFnoBjewjLxf6bcuW/EM1TnPohnNmI0LRHdQ/q";
      isNormalUser = true;
      description = userDescription;
      extraGroups = [ "libvirtd" "lp" "networkmanager" "scanner" "vboxusers" "wheel" "yubikey" ];
      group = username;
    };
  };  
}
