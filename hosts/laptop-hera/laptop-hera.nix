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
