{ config, lib, pkgs, ... }:

with lib;
{
  # Block-level btrfs deduplication (bees). Game libraries are per Linux user
  # now (games/steam.nix), so each account keeps its own copy under
  # ~/.local/share/Steam; bees collapses the identical data back to one copy
  # in the background, without Steam or Wine noticing.
  #
  # One instance per btrfs filesystem. On these hosts /, /home and /nix (plus
  # the legacy /steamlib and the /home snapshots) are subvolumes of a single
  # btrfs filesystem, so one instance covers them all. The bees service
  # wrapper mounts subvolid=5 itself, which is why pointing at "/" is enough
  # even where / is subvol=@.
  services.beesd.filesystems.btrfs = {
    spec = "/";
    hashTableSizeMB = 1024; # 1 GiB RAM; 16 KiB extents, plenty for game data
    verbosity = "warning";
    # Be gentle: the laptops are used interactively while bees runs.
    extraOptions = [ "--loadavg-target" "5.0" ];
  };
}
