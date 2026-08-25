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

  users.groups.syncthing.members = [ "nicky" "aeiuno" ];

  networking.firewall.allowedTCPPorts = [
    8384 # syncthing web UI
  ];

  systemd.tmpfiles.rules = [
    # 2770 (no "others" access): only the syncthing group (parents) can reach
    # /sync; sven/aaron get no access at all.
    "d /sync 2770 syncthing syncthing -"
    # Default ACL: new synced files inherit group rwx and are never
    # world-readable, so kids can't read them via the "others" bits.
    "A /sync 2770 syncthing syncthing - u::rwx,g::rwx,o::---"
    "d /var/lib/syncthing 0700 syncthing syncthing -"
  ];
}
