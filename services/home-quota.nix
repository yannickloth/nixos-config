{ config, lib, pkgs, ... }:

{
  # Per-user disk quotas on /home via btrfs project quotas (per-directory).
  # Each kid gets a project id and a hard cap so they can't fill the disk;
  # parents are not limited.
  #
  # quota-tools' setquota -P limits are in 1024-byte units:
  #   50 GiB = 50 * 2^30 / 1024 = 52428800.
  # All commands are guarded: if the kernel/filesystem lacks project-quota
  # support, activation still succeeds but prints a warning (nothing is
  # enforced silently). Verify on the host with
  #   sudo btrfs quota enable -p /home   # (idempotent)
  #   sudo btrfs qgroup show -p /home    # project qgroups + usage
  system.activationScripts.btrfs-user-quotas = {
    deps = [ "users" ];
    text = ''
      warn() {
        echo "home-quota: $* failed; project quotas are NOT enforced" >&2
      }

      ${pkgs.btrfs-progs}/bin/btrfs quota enable -p /home 2>/dev/null || warn "btrfs quota enable -p"
      ${pkgs.quota}/bin/quotaon -P /home 2>/dev/null || warn "quotaon -P"

      # sven: project id 2001, 50 GiB hard limit, inherited by new files
      ${pkgs.e2fsprogs}/bin/chattr -p 2001 -R /home/sven 2>/dev/null || warn "chattr -p 2001 /home/sven"
      ${pkgs.e2fsprogs}/bin/chattr +P -R /home/sven 2>/dev/null || warn "chattr +P /home/sven"
      ${pkgs.quota}/bin/setquota -P 2001 0 52428800 0 0 /home 2>/dev/null || warn "setquota -P 2001"

      # aaron: project id 2002, 50 GiB hard limit, inherited by new files
      ${pkgs.e2fsprogs}/bin/chattr -p 2002 -R /home/aaron 2>/dev/null || warn "chattr -p 2002 /home/aaron"
      ${pkgs.e2fsprogs}/bin/chattr +P -R /home/aaron 2>/dev/null || warn "chattr +P /home/aaron"
      ${pkgs.quota}/bin/setquota -P 2002 0 52428800 0 0 /home 2>/dev/null || warn "setquota -P 2002"
    '';
  };
}
