{ lib, ... }:

with lib;
{
  imports = [
    # Include the results of the hardware scan.
    ./hardware-configuration.nix

    # Shared family-laptop module set (IVP; see the file header for the deltas).
    ../../environments/family-laptop.nix

    # Pinned age host identity (services/host-age.nix): the keypair in
    # ssh-keys/hosts/laptop-hera is pinned as the /etc/ssh host key (private key installed per
    # secrets-structure/README.md) and audited against secrets.nix at build time.
    ../../services/host-age.nix
    {
      services.hostAge = {
        enable = true;
        pubKey = ../../ssh-keys/hosts/laptop-hera.pub;
      };
    }

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

  # laptop-hera predates the fleet UID convention: aeiuno is 1000 and nicky is
  # 1001 (the fleet has aeiuno=1001, nicky=1000). The user modules
  # (users/aeiuno/aeiuno.nix, users/nicky/nicky.nix) declare the fleet values;
  # mkForce overrides them here so NixOS does not warn that existing user UIDs
  # on disk do not match the config, and home-manager's auto-resolution of
  # home.uid from the NixOS config then picks up the correct values.
  users.users.aeiuno.uid = mkForce 1000;
  users.users.nicky.uid  = mkForce 1001;

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
  # before mounts at boot, so the bind source is created by a unit ordered
  # between /data and /sync (the activation script below only handles the
  # legacy /sync symlink migration at switch time).
  systemd.services.syncthing-hera-data-dir = {
    description = "Create the /data/syncthing bind source before /sync mounts";
    wantedBy = [ "sync.mount" ];
    requires = [ "data.mount" ];
    after = [ "data.mount" ];
    before = [ "sync.mount" ];
    # This unit sits in the local-fs chain (before sync.mount), but a service
    # with default dependencies is ordered After=basic.target and
    # Requires=sysinit.target. nix-daemon.socket is itself ordered after
    # sysinit.target, so the two together form an ordering cycle:
    #   nix-daemon.socket -> sysinit.target -> local-fs.target -> sync.mount
    #   -> this unit -> basic.target -> sockets.target -> nix-daemon.socket
    # systemd breaks it by deleting the nix-daemon.socket start job, so the
    # nix daemon never listens and every home-manager-<user>.service fails at
    # boot with "cannot connect to socket at /nix/var/nix/daemon-socket/socket".
    # Dropping the default dependencies keeps the unit purely in the mount chain.
    unitConfig.DefaultDependencies = false;
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      mkdir -p /data/syncthing
      chown syncthing:syncthing /data/syncthing
      chmod 2770 /data/syncthing
    '';
  };

  # One-time migration: if the legacy /sync symlink is still there, swap it for
  # the mount point dir (the bind mount itself is handled by the unit above).
  system.activationScripts.syncthing-hera-data = {
    deps = [ "users" "groups" ];
    text = ''
      if [ -L /sync ]; then
        rm /sync
        mkdir -p /sync
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

  # Bootloader — keep 2 generations max to prevent EFI partition fill-up:
  # the ESP is 511M and one kernel+initrd set is ~156M (the initrd alone is
  # ~143M), so 5 generations of distinct kernels could not fit.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.loader.systemd-boot.configurationLimit = 2;

  # 64 GiB RAM -> parallel builds with all cores.
  roles.nix.maxJobs = 12;
  roles.nix.cores = 0;

  nix.settings = {
    download-buffer-size = 524288000;
  };
}
