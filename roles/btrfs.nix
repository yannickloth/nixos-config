# Btrfs filesystem improvements — applied to every host (all five use btrfs).
#
# Two things to know:
#
# 1. TRIM: already covered by nixpkgs. services.fstrim is enabled by
#    default and runs the weekly systemd-fstrim.timer, which trims every
#    mounted filesystem that supports it. We deliberately do NOT add
#    discard=async to the mount options: there is no generic way to
#    inject options into "all btrfs mounts" (a fileSystems definition
#    reading config.fileSystems is infinite recursion), and continuous
#    discard is not recommended on server btrfs (write amplification) —
#    the weekly fstrim is the standard practice.
#
# 2. Scrub: weekly auto-scrub to detect and correct silent bit rot.
#    NixOS' built-in default for services.btrfs.autoScrub.fileSystems
#    already covers every btrfs mount point, deduplicated per device —
#    so a layout with several subvolumes on one disk (e.g. /, /home,
#    /nix) is scrubbed exactly once. We only enable the service and
#    pick the schedule; overriding fileSystems with all mount points
#    would scrub each device once per subvolume.
{ config, lib, ... }:

with lib;

let
  cfg = config.btrfs.role;
in
{
  options.btrfs.role = {
    enable = mkEnableOption "btrfs filesystem improvements" // { default = true; };

    # btrfs auto-scrub reads all data and metadata to detect and correct
    # silent bit rot. Runs weekly by default.
    autoScrub.enable = mkEnableOption "btrfs auto-scrub" // { default = true; };
    autoScrub.interval = mkOption {
      type = types.str;
      default = "weekly";
      description = "Cron-style schedule for btrfs scrub.";
    };
  };

  config = mkIf cfg.enable {
    services.btrfs.autoScrub = mkIf cfg.autoScrub.enable {
      enable = true;
      interval = cfg.autoScrub.interval;
    };
  };
}
