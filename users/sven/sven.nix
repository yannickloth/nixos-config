{ config, pkgs, ... }:
let
  username = "sven";
  userDescription = "sven";
in
{
  security.pam.services.sven.logFailures = true;
  users = {
    groups.sven = {
      name = username;
    };
    users.sven = {
      isNormalUser = true; # Indicates whether this is an account for a "real" user. This automatically sets group to users, createHome to true, home to /home/«username», useDefaultShell to true, and isSystemUser to false. Exactly one of isNormalUser and isSystemUser must be true.
      hashedPassword = "$6$VCPjZcI/NmVYK4I7$MytOHmyNfdCjn4LNbT6JZO0Tx2gsJtNpumif9hsV5w3ZmXpHWMyygTq2NetJAEUekG7qfMfWvfvUmvwXn3swG1";
      description = userDescription;
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
