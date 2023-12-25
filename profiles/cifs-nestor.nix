{ config, lib, pkgs, modulesPath, ... }:

{
  fileSystems."/nestor/DA" = {
      device = "//nestor.bee-blues.ts.net/usbshare1/DA/";
      fsType = "cifs";
      options = let
        # this line prevents hanging on network split
        automount_opts = "x-systemd.automount,noauto,x-systemd.idle-timeout=60,x-systemd.device-timeout=5s,x-systemd.mount-timeout=5s";
      in ["${automount_opts},credentials=/etc/nixos/smb-secrets,uid=1000"];
  };
  fileSystems."/nestor/multimedia" = {
      device = "//nestor.bee-blues.ts.net/multimedia/";
      fsType = "cifs";
      options = let
        # this line prevents hanging on network split
        automount_opts = "x-systemd.automount,noauto,x-systemd.idle-timeout=60,x-systemd.device-timeout=5s,x-systemd.mount-timeout=5s";
      in ["${automount_opts},credentials=/etc/nixos/smb-secrets,uid=1000"];
  };
}
