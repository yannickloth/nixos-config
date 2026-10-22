{ config, lib, ... }:

with lib;

{
  config = {
    networking = {
      # enable networkmanager on all workstations
      networkmanager = {
        enable = lib.mkForce true;
      };
      # enable resolvconf
      resolvconf.enable = true;

      # NetworkManager's default Wi-Fi backend is the system wpa_supplicant,
      # controlled over DBus: nixpkgs' NM module sets `wireless.enable = true`
      # for it, so we match with mkDefault (forcing it would fight a host that
      # deliberately selects the iwd backend or disables wireless).
      wireless.enable = lib.mkDefault true;
    };
  };
}
