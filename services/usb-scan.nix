# Virus-scan USB drives with ClamAV when they are inserted.
#
# - A udev rule forces removable (USB) filesystems to mount read-only via
#   udisks2/KDE (UDISKS_MOUNT_OPTIONS), so nothing can be written before a scan.
# - A second udev rule starts usb-scan@<device>.service on insertion, which
#   scans the mounted filesystem and reports the result to the active user.
#
# Parents who need write access can `sudo mount -o remount,rw` the drive (or
# mount it with an authenticated `udisksctl`) — kids cannot.
{ config, lib, pkgs, ... }:

{
  services.udev.extraRules = ''
    # Mount USB storage read-only via udisks2/KDE.
    SUBSYSTEM=="block", ENV{ID_BUS}=="usb", ENV{ID_FS_TYPE}!="", ENV{UDISKS_MOUNT_OPTIONS}="ro,nosuid,noexec"
    # Trigger the scan service when a USB filesystem appears.
    ACTION=="add", SUBSYSTEM=="block", ENV{ID_BUS}=="usb", ENV{ID_FS_TYPE}!="", TAG+="systemd", ENV{SYSTEMD_WANTS}+="usb-scan@%k.service"
  '';

  systemd.services."usb-scan@" = {
    description = "ClamAV scan of an inserted USB drive";
    after = [ "local-fs.target" ];
    path = with pkgs; [ bash clamav libnotify util-linux systemd sudo gawk gnugrep coreutils ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pkgs.bash}/bin/bash ${./usb-scan.sh} %i";
    };
  };
}
