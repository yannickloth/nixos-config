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

    # Fix: network-local-commands.service is wanted by network.target and
    # starts after network-pre.target. NetworkManager.service also starts
    # after network-pre.target but has Before=network.target. The window
    # between network-pre.target and network.target is only ~97ms, but NM
    # takes ~423ms to start. Without this ordering, systemd cannot fit NM
    # into the window and skips it entirely. By making
    # network-local-commands.service start after NM, network.target is
    # reached only after NM finishes.
    systemd.services.network-local-commands = {
      after = [ "NetworkManager.service" ];
    };
  };
}
