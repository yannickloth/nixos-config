{ config, pkgs, ... }:
let 
  username="nicky";
  userDescription="nicky";
in
{
  security.pam.services.nicky.logFailures = true;
  users = {
    groups.nicky = {
      name = username;
    };
    users.nicky = {
      createHome = true;
      hashedPassword = "$2b$05$.x8gLS6s8Vd2qFsPFnoBjewjLxf6bcuW/EM1TnPohnNmI0LRHdQ/q";
      isNormalUser = true;
      description = userDescription;
      extraGroups = [ "libvirtd" "lp" "networkmanager" "podman" "scanner" "vboxusers" "wheel" "yubikey" ];
      group = username;
    };
  };  
}
