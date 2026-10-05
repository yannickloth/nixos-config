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

  # Syncthing device name for this host (see services/syncthing/pool.nix).
  services.syncthing.self = "laptop-hera";
  # Syncthing web-UI login username (the password comes from the agenix secret).
  services.syncthing.guiUser = "syncthing";

  # The root volume has no room for the syncthing tree, so it lives on the
  # second disk. Keep the canonical /sync path used by
  # services/syncthing/default.nix identical on every host by making /sync a
  # symlink to /data/syncthing here; only the backing store differs. The
  # module's /sync tmpfiles/ACL rules and the ~/sync symlinks follow the
  # symlink, so they need no changes. Re-asserted every activation (runs at
  # boot too), and never removes a non-empty /sync — the one-time migration
  # below must move the data first.
  system.activationScripts.syncthing-hera-data = {
    deps = [ "users" "groups" ];
    text = ''
      # Only act when the data disk is actually mounted; otherwise leave /sync
      # alone rather than creating a stray dir on the root volume.
      if mountpoint -q /data; then
        mkdir -p /data/syncthing
        chown syncthing:syncthing /data/syncthing
        chmod 2770 /data/syncthing
        if [ ! -L /sync ]; then
          rmdir /sync 2>/dev/null || true
          ln -sfn /data/syncthing /sync
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
