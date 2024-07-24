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
      isNormalUser = true; # Indicates whether this is an account for a “real” user. This automatically sets group to users, createHome to true, home to /home/«username», useDefaultShell to true, and isSystemUser to false. Exactly one of isNormalUser and isSystemUser must be true.
      hashedPassword = "$2b$05$.x8gLS6s8Vd2qFsPFnoBjewjLxf6bcuW/EM1TnPohnNmI0LRHdQ/q";
      description = userDescription;
      extraGroups = [
                      "users" "wheel"
                    ]
                    ++ (if (config.programs.adb.enable == true) then [ "adbusers" ] else []) # for Android debugging
                    ++ (if (config.programs.gamemode.enable == true) then [ "gamemode" ] else []) # for gamemode CPU governor setting
                    ++ (if (config.networking.networkmanager.enable == true) then [ "networkmanager" ] else [])
                    ++ (if (config.virtualisation.libvirtd.enable == true) then [ "kvm" "libvirtd" ] else [])
                    ++ (if (config.virtualisation.podman.enable == true) then [ "podman" ] else [])
                    ++ (if (config.hardware.sane.enable == true) then [ "lp" "scanner" ] else []) # for scanning
                    ++ (if (config.virtualisation.virtualbox.host.enable == true) then [ "vboxusers" ] else [])
                    ++ (if (config.users.extraGroups.yubikey != null) then [ "yubikey" ] else []);
      group = username;
    };
  };
}
