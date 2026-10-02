# Groups every family account should join, derived from which services/features
# are enabled on the host. Previously this conditional block was copy-pasted
# into each of users/{nicky,aeiuno,sven,aaron}/*.nix (IVP: same change-driver
# set kept apart).
#
# User modules consume it as:
#   extraGroups = base ++ config.users.commonExtraGroups;
# where base is [ "users" "wheel" ] for adults and [ "users" ] for kids.
{ config, lib, ... }:

with lib;

{
  options.users.commonExtraGroups = mkOption {
    type = types.listOf types.str;
    default = [ ];
    example = [ "gamemode" "networkmanager" ];
    description = "Extra groups every family account joins, based on enabled services.";
  };

  config.users.commonExtraGroups =
    optionals config.programs.gamemode.enable [ "gamemode" ] # gamemode CPU governor
    ++ optionals config.networking.networkmanager.enable [ "networkmanager" ]
    ++ optionals config.virtualisation.libvirtd.enable [ "kvm" "libvirtd" ] # kvm: Intel GVT-g vGPU access without root
    ++ optionals config.virtualisation.podman.enable [ "podman" ]
    ++ optionals config.hardware.sane.enable [ "lp" "scanner" ] # scanning
    ++ optionals config.virtualisation.virtualbox.host.enable [ "vboxusers" ]
    ++ optionals (config.users.extraGroups ? yubikey) [ "yubikey" ]
    ++ optionals config.security.tpm2.enable [ "tss" ]; # tss group has access to TPM devices
}
