{ config, lib, pkgs, ... }:

with lib;
{
  imports = [
    # Include the results of the hardware scan.
    ./hardware-configuration.nix

    # Shared family-laptop module set (IVP; see the file header for the deltas).
    ../../environments/family-laptop.nix

    # laptop-xps-only modules (SONOS controller + extra Plasma packages; the
    # 16 GiB host also runs the lighter Plasma session).
    ../../apps/noson.nix
    ../../desktop/plasma.nix

    # commonHm.hostName: home-manager modules cannot reach
    # config.networking.hostName, so the host name is passed explicitly.
    {
      home-manager.users.aeiuno = {
        imports = [ ../../users/aeiuno/aeiuno-hm.nix ];
        commonHm.hostName = "laptop-xps";
      };
    }
    {
      home-manager.users.nicky = {
        imports = [ ../../users/nicky/nicky-hm.nix ];
        commonHm.hostName = "laptop-xps";
      };
    }
    {
      home-manager.users.sven = {
        imports = [ ../../users/sven/sven-hm.nix ];
        commonHm.hostName = "laptop-xps";
      };
    }
    {
      home-manager.users.aaron = {
        imports = [ ../../users/aaron/aaron-hm.nix ];
        commonHm.hostName = "laptop-xps";
      };
    }
  ];
  # In this file comes everything that is specific to this host.
  networking.hostName = "laptop-xps"; # Define your hostname.

  # Syncthing device name for this host (see services/syncthing/pool.nix).
  services.syncthing.self = "laptop-xps";

  # 16 GiB RAM -> keep browser profiles on disk (psd disabled).
  roles.psd.enable = false;

  # Bootloader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # Btrfs swapfile on the root filesystem (in addition to zram) as disk-swap overflow.
  swapDevices = [{ device = "/swapfile"; size = 16384; }]; # 16 GiB; adjust to match RAM/disk

  # 16 GiB RAM -> 25% zram (shared default is 50%, sized for >=64 GiB hosts).
  # Keeps page cache RAM free while still giving compressed overflow on top of the swapfile.
  zramSwap.memoryPercent = 25;

  # Trim SSD (NVMe) weekly to keep free-space performance and endurance up.
  services.fstrim.enable = true;

  # Family-safe DNS (Cloudflare Family 1.1.1.3 / 1.0.0.3, blocks malware + adult content).
  # Note: DNS applies machine-wide, not per-user.
  networking.networkmanager.insertNameservers = [ "1.1.1.3" "1.0.0.3" ];

  # Suspend on lid close. suspend-then-hibernate is NOT enabled because NixOS
  # cannot resume a hibernation image from a btrfs swapfile (no resume_offset
  # support) on this LUKS setup; it would need a dedicated swap partition.
  services.logind.settings.Login.HandleLidSwitch = "suspend";
  systemd.sleep.settings.Sleep = {
    HibernateDelaySec = "1h"; # ready for when a hibernation-capable swap partition is added
  };

  # 16 GiB RAM -> cap concurrent builds to avoid OOM during rebuilds (4 cores/8 threads).
  roles.nix.maxJobs = 4;
}
