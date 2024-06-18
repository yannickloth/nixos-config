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
      extraGroups = [
                      "wheel"
                    ]
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
