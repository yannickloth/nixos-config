{ config, lib, pkgs, ... }:

{
  # Nightly read-only btrfs snapshots of /home into /.snapshots/home (kept 14),
  # so anything a kid breaks or installs in their home can be rolled back.
  #
  # Restore an old home, e.g.:
  #   sudo btrfs subvolume snapshot -r /.snapshots/home/home-20260823-033000 /mnt/home-restore
  #   # then boot from a live media / alternate subvol and swap /home, or copy files out.
  systemd.timers.home-snapshots = {
    description = "Nightly read-only snapshot of /home";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "*-*-* 03:30:00";
      Persistent = true;
      RandomizedDelaySec = "15m";
    };
  };

  systemd.services.home-snapshots = {
    description = "Create and prune read-only snapshots of /home";
    after = [ "local-fs.target" ];
    serviceConfig = {
      Type = "oneshot";
    };
    path = [ pkgs.btrfs-progs pkgs.coreutils ];
    script = ''
      set -eu
      snaproot="/.snapshots/home"
      mkdir -p "$snaproot"
      name="home-$(date +%Y%m%d-%H%M%S)"
      ${pkgs.btrfs-progs}/bin/btrfs subvolume snapshot -r /home "$snaproot/$name"
      # Prune: delete the oldest beyond the 14 most recent (names sort lexically).
      find "$snaproot" -mindepth 1 -maxdepth 1 -type d -name 'home-*' | sort | head -n -14 \
        | while read -r s; do
            ${pkgs.btrfs-progs}/bin/btrfs subvolume delete "$s"
          done
    '';
  };
}
