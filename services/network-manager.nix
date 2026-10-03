{ config, lib, ... }:

with lib;

{
  config = {
    networking = {
      # enable networkmanager on all workstations and use local dnsmasq server
      networkmanager = {
        enable = lib.mkForce true;

        appendNameservers = ["9.9.9.9" "1.1.1.1"];
      };
      # enable resolvconf
      resolvconf.enable = true;

      # NetworkManager's default Wi-Fi backend is the system wpa_supplicant,
      # controlled over DBus: nixpkgs' NM module sets `wireless.enable = true`
      # for it, so we must match — and use mkForce because nixpkgs sets it at
      # plain priority. Without this no wpa_supplicant service runs and Wi-Fi
      # breaks (this became necessary with the nixpkgs 26.05 bump). The previous
      # "disable wpasupplicant" comment was simply wrong.
      wireless.enable = lib.mkForce true;
    };

    # enable dnsmasq for dns caching server
    services.dnsmasq = {
      #enable = mkDefault true;
      enable = false;

      # additional secure configuration for dnsmasq
#       extraConfig = ''
#         strict-order # obey strict order of dns servers
#       '';
      settings = {
        server = [
          "192.168.178.200"
          "192.168.178.1"
          "9.9.9.9"
          "1.1.1.1"
        ];
        strict-order = true; # obey strict order of dns servers
      };
    };    
  };
}
