{ config, lib, pkgs, ... }:

with lib;

{
  services.syncthing = {
    enable = true;
    user = "syncthing";
    group = "syncthing";
    dataDir = "/sync";
    configDir = "/var/lib/syncthing";
    guiAddress = "0.0.0.0:8384";
    openDefaultPorts = true;
    overrideDevices = false; # keep devices added via the web UI
    overrideFolders = false; # keep folders added via the web UI
    settings.options = {
      localAnnounceEnabled = true;
      relaysEnabled = true;
      urAccepted = -1;
    };
  };

  users.groups.syncthing.members = [ "nicky" "aeiuno" "sven" "aaron" ];

  networking.firewall.allowedTCPPorts = [
    8384 # syncthing web UI
  ];

  systemd.tmpfiles.rules = [
    "d /sync 2775 syncthing syncthing -"
    "d /var/lib/syncthing 0700 syncthing syncthing -"
  ];
}
