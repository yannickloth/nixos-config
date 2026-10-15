{ config, lib, pkgs, ... }:

with lib;
{
  imports = [
    # Include the results of the hardware scan.
    ./hardware-configuration.nix

    # Shared family-laptop module set (IVP; see the file header for the deltas).
    ../../environments/family-laptop.nix

    # laptop-hera-only modules.
    ../../apps/benchmark.nix

    # commonHm.hostName: home-manager modules cannot reach
    # config.networking.hostName, so the host name is passed explicitly.
    {
      home-manager.users.aeiuno = {
        imports = [ ../../users/aeiuno/aeiuno-hm.nix ];
        commonHm.hostName = "laptop-hera";
      };
    }
    {
      home-manager.users.nicky = {
        imports = [ ../../users/nicky/nicky-hm.nix ];
        commonHm.hostName = "laptop-hera";
      };
    }
    {
      home-manager.users.sven = {
        imports = [ ../../users/sven/sven-hm.nix ];
        commonHm.hostName = "laptop-hera";
      };
    }
    {
      home-manager.users.aaron = {
        imports = [ ../../users/aaron/aaron-hm.nix ];
        commonHm.hostName = "laptop-hera";
      };
    }
  ];
  # In this file comes everything that is specific to this host.
  networking.hostName = "laptop-hera"; # Define your hostname.

  # nicky's per-user services must survive logout so Unsloth Studio's local
  # System One API (packages/unsloth-studio/home.nix) serves whoever is
  # logged in — same reason laptop-p16 lingers nicky (Orca runtime server).
  users.users.nicky.linger = true;

  # Syncthing device name for this host (see services/syncthing/pool.nix).
  services.syncthing.self = "laptop-hera";
  # Syncthing web-UI login username (the password comes from the agenix secret).
  services.syncthing.guiUser = "syncthing";

  # The root volume has no room for the syncthing tree, so it lives on the
  # second disk. Bind-mount it at the canonical /sync path used by
  # services/syncthing/default.nix, so only the backing store differs between
  # hosts. This replaces the previous /sync -> /data/syncthing symlink, which
  # raced the module's `mkdir -p /sync` activation script (alphabetical script
  # order created a real /sync first, and the silent rmdir/ln conversion then
  # degraded into a nested /sync/syncthing symlink). With a bind mount there
  # is no conversion left to race: /sync is a plain mount point, systemd
  # orders it after /data by itself, and tmpfiles/ACL rules apply unchanged.
  fileSystems."/sync" = {
    device = "/data/syncthing";
    fsType = "none";
    options = [ "bind" ];
    depends = [ "/data" ];
  };

  # systemd mount units do not create their bind source, and activation runs
  # before mounts at boot, hence the mountpoint guard. One-time migration: if
  # the legacy /sync symlink is still there, swap it for the mount point dir
  # (order-independent with the module's `mkdir -p /sync`, which no-ops on the
  # resulting directory). Once /sync is the bind mount this branch never fires.
  system.activationScripts.syncthing-hera-data = {
    deps = [ "users" "groups" ];
    text = ''
      if mountpoint -q /data; then
        mkdir -p /data/syncthing
        chown syncthing:syncthing /data/syncthing
        chmod 2770 /data/syncthing
        if [ -L /sync ]; then
          rm /sync
          mkdir -p /sync
        fi
      else
        echo "syncthing-hera-data: /data not mounted; leaving /sync untouched" >&2
      fi
    '';
  };

  # 64 GiB RAM -> run browser profiles in RAM.
  roles.psd.enable = true;

  # 64 GiB RAM -> /tmp in RAM. Volatile by nature, so no cleanOnBoot wipe
  # (deleting psd's tens of thousands of small profile files was slow at boot).
  boot.tmp.useTmpfs = true;
  boot.tmp.tmpfsSize = "50%";
  boot.tmp.cleanOnBoot = false;

  # Bootloader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # 64 GiB RAM -> parallel builds with all cores.
  roles.nix.maxJobs = 12;
  roles.nix.cores = 0;

  nix.settings = {
    download-buffer-size = 524288000;
  };
}
