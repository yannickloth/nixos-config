{ config, lib, pkgs, ... }:

{
  # Per-user disk quotas on /home via btrfs project quotas (per-directory).
  # Each kid gets a project id and a hard cap so they can't fill the disk;
  # parents are not limited.
  #
  # Values are in 1K blocks (setquota units): 50 GiB = 52428800.
  # All commands are guarded: if the kernel/filesystem lacks project-quota
  # support, nothing is enforced and nothing breaks. Verify on the host with
  #   sudo btrfs quota enable -P /home   # (idempotent)
  #   sudo btrfs qgroup show -p /home    # project qgroups + usage
  system.activationScripts.btrfs-user-quotas = {
    deps = [ "users" ];
    text = ''
      ${pkgs.btrfs-progs}/bin/btrfs quota enable -P /home 2>/dev/null || true
      ${pkgs.quota}/bin/quotaon -P /home 2>/dev/null || true

      # sven: project id 2001, 50 GiB hard limit
      ${pkgs.e2fsprogs}/bin/chattr -p 2001 -R /home/sven 2>/dev/null || true
      ${pkgs.quota}/bin/setquota -P 2001 0 52428800 0 0 /home 2>/dev/null || true

      # aaron: project id 2002, 50 GiB hard limit
      ${pkgs.e2fsprogs}/bin/chattr -p 2002 -R /home/aaron 2>/dev/null || true
      ${pkgs.quota}/bin/setquota -P 2002 0 52428800 0 0 /home 2>/dev/null || true
    '';
  };
}
