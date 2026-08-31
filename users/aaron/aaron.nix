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
      # TODO: replace with a real password hash (openssl passwd -6 '<password>').
      hashedPassword = "$6$AkAhumLiySn.FYR8$SWTfZTUbwSKXvTFC.b2S/2Ss1zzYvfJCr9YoKT.oE3QoXCvX6IG8pZRdrB.UvV2cQ6UxFAm4mjz0WlorwVug30";
      description = userDescription;
      shell = pkgs.zsh;
      extraGroups = [
        "users"
      ]
      ++ (if (config.programs.gamemode.enable == true) then [ "gamemode" ] else [ ]) # for gamemode CPU governor setting
      ++ (if (config.networking.networkmanager.enable == true) then [ "networkmanager" ] else [ ])
      ++ (if (config.virtualisation.libvirtd.enable == true) then [
        "kvm" # This allows users to access virtual sliced GPUs (Intel GVT-g) without root.
        "libvirtd"
      ] else [ ])
      ++ (if (config.virtualisation.podman.enable == true) then [ "podman" ] else [ ])
      ++ (if (config.hardware.sane.enable == true) then [ "lp" "scanner" ] else [ ]) # for scanning
      ++ (if (config.virtualisation.virtualbox.host.enable == true) then [ "vboxusers" ] else [ ])
      ++ (if (config.users.extraGroups.yubikey != null) then [ "yubikey" ] else [ ])
      ++ (if (config.security.tpm2.enable == true) then [ "tss" ] else [ ]) # tss group has access to TPM devices
      ;
      group = username;
    };
  };
}
