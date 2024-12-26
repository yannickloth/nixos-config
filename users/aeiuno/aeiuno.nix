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
      isNormalUser = true; # isNormalUser = true; # Indicates whether this is an account for a “real” user. This automatically sets group to users, createHome to true, home to /home/«username», useDefaultShell to true, and isSystemUser to false. Exactly one of isNormalUser and isSystemUser must be true.
      hashedPassword = "$2b$05$YGHKsI8io3H9wIbbN8KwAOX5woC8hZItpSAmLLcxG0sPdO6akjht2";
      description = userDescription;
      extraGroups = [
                      "users" "wheel"
                    ]
                    ++ (if (config.programs.gamemode.enable == true) then [ "gamemode" ] else []) # for gamemode CPU governor setting
                    ++ (if (config.networking.networkmanager.enable == true) then [ "networkmanager" ] else [])
                    ++ (if (config.virtualisation.libvirtd.enable == true) then [ 
                      "kvm" # This allows users to access virtual sliced GPUs (Intel GVT-g) without root.
                      "libvirtd" ] else [])
                    ++ (if (config.virtualisation.podman.enable == true) then [ "podman" ] else [])
                    ++ (if (config.hardware.sane.enable == true) then [ "lp" "scanner" ] else []) # for scanning
                    ++ (if (config.virtualisation.virtualbox.host.enable == true) then [ "vboxusers" ] else [])
                    ++ (if (config.users.extraGroups.yubikey != null) then [ "yubikey" ] else []);
      group = username;
    };
  };  
}
