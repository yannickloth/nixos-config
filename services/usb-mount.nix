# Make detachable (USB) drives mountable read-write by regular users.
#
# Users mount removable drives through udisks2: `udisksctl mount`, and the
# Plasma "Devices" notifier. Three separate things stopped NTFS drives there.
#
# 1. Windows leaves the NTFS dirty flag set on every drive that is unplugged
#    without a safe removal. The in-tree ntfs3 driver then refuses the
#    read-write mount ("ntfs3: Volume is dirty and 'force' flag is not set!")
#    and udisks2 reports a mount error. A udev rule now runs `ntfsfix -d` on
#    insertion, which clears the flag before udisks2 or Plasma tries to mount.
# 2. udisks2 checks every mount option against a per-driver allow list
#    (/etc/udisks2/mount_options.conf). ntfs3's `force` and ntfs-3g's
#    `remove_hiberfile` were not listed, so a user could not ask for them. They
#    are listed now, as an escape hatch behind ntfsfix.
# 3. The ntfs-3g FUSE driver is the fallback when ntfs3 refuses. udisks2 runs it
#    as root, and a root-mounted FUSE filesystem is invisible to everyone else
#    unless /etc/fuse.conf allows allow_other. programs.fuse.userAllowOther
#    uncomments that line.
#
# ClamAV still scans every inserted USB filesystem (services/usb-scan.nix) and
# reports the result to the user. The scan is read-only; the drive itself is now
# read-write, as `noexec` and `nosuid` stay set.
{ config, lib, pkgs, ... }:

{
  config = {
    # udisks2 is pulled in by nixpkgs' Plasma 6 module (services/desktop-managers/
    # plasma6.nix). Declare it here too, so the removable-media stack does not
    # depend on which desktop module a host imports.
    services.udisks2.enable = true;

    # ntfs3 is the in-tree kernel driver. For the same signature, nixpkgs also
    # installs the ntfs-3g userspace tools (mount.ntfs, ntfsfix, ntfsinfo),
    # which is the FUSE fallback and what the udev rule below uses.
    boot.supportedFilesystems = [ "ntfs" ];

    # Allow a root-mounted FUSE filesystem to be read by other users, which is
    # how udisks2 hands an ntfs-3g mount to the user who asked for it.
    programs.fuse.userAllowOther = true;

    services.udev.extraRules = ''
      # Clear the NTFS dirty flag on insertion so the read-write mount succeeds.
      # ntfsfix only writes when the volume is marked dirty, and udev runs it
      # while the add event is processed, before udisks2/Plasma mounts the volume.
      SUBSYSTEM=="block", ACTION=="add", ENV{ID_BUS}=="usb", ENV{ID_FS_TYPE}=="ntfs", RUN+="${pkgs.ntfs3g}/sbin/ntfsfix -d /dev/%k"
      # Mount USB storage read-write for the user, without setuid and exec.
      # udisks 2.10+ reads UDISKS_MOUNT_OPTIONS_<group> only; the bare
      # UDISKS_MOUNT_OPTIONS property from the older interface is ignored.
      SUBSYSTEM=="block", ENV{ID_BUS}=="usb", ENV{ID_FS_TYPE}!="", ENV{UDISKS_MOUNT_OPTIONS_defaults}="rw,nosuid,noexec"
    '';

    services.udisks2.settings."mount_options.conf" = {
      defaults = {
        # The lists replace the built-in ones, so each list repeats the
        # built-in entries and adds what users need. The udisks package ships a
        # reference at etc/udisks2/mount_options.conf.example.
        "ntfs:ntfs3_defaults" = [ "uid=$UID" "gid=$GID" ];
        "ntfs:ntfs3_allow" = [
          "uid=$UID"
          "gid=$GID"
          "umask"
          "dmask"
          "fmask"
          "iocharset"
          "discard"
          "nodiscard"
          "sparse"
          "nosparse"
          "prealloc"
          "noprealloc"
          "showmeta"
          "noshowmeta"
          "sys_immutable"
          "nosys_immutable"
          "hide_dot_files"
          "nohide_dot_files"
          "windows_names"
          "nocase"
          "case"
          "force" # mount a volume that is still marked dirty
        ];
        "ntfs:ntfs_defaults" = [ "uid=$UID" "gid=$GID" "windows_names" ];
        "ntfs:ntfs_allow" = [
          "uid=$UID"
          "gid=$GID"
          "umask"
          "dmask"
          "fmask"
          "locale"
          "norecover"
          "ignore_case"
          "windows_names"
          "compression"
          "nocompression"
          "big_writes"
          "force" # mount a volume that is still marked dirty
          "remove_hiberfile" # volume was hibernated by Windows
        ];
      };
    };
  };
}
