# Hand-maintained hardware config for server-nike (Dell Precision Tower 5810).
# Values transcribed from the running system (lsblk, /etc/nixos, /sys).
#
# Dell Precision Tower 5810 hardware (serial J35FZG2):
# - CPU: Xeon E5-1650 v3 (Haswell-EP, 3.5 GHz)
# - GPU: NVIDIA RTX 3060 12GB (Ampere GA106, sm_86) — PCIe 3.0 x16, Slot 1 (only GPU)
#   - the former NVIDIA GT 730 (Kepler) in Slot 3 was removed
# - RAM: DDR4 ECC Registered (Xeon platform)
# - Storage:
#   - sdb (1.8T): /boot (vfat), LUKS root (btrfs: /, /home, /nix subvolumes), LUKS swap
#   - sda (1.8T): LUKS data disk (btrfs) at /data, keyfile-unlocked from the root
# - Network: DHCP
{ config, lib, pkgs, modulesPath, ... }:

{
  imports =
    [
      (modulesPath + "/installer/scan/not-detected.nix")
    ];

  boot = {
    blacklistedKernelModules = lib.optionals (!config.hardware.enableRedistributableFirmware) [
      "ath3k"
    ];
    initrd = {
      # From the nixos-generate-config scan of this machine, plus the LUKS
      # crypto modules.
      availableKernelModules = [
        "xhci_pci"
        "ehci_pci"
        "ahci"
        "usbhid"
        "uas"
        "sd_mod"
        "usb_storage"
        "aesni_intel" # LUKS decryption in initrd
        "cryptd"      # LUKS decryption in initrd
      ];
      kernelModules = [
        "nvidia"
        "nvidia_modeset"
        "nvidia_drm"
        "nvidia_uvm"
      ];
      luks.devices = {
        # Root disk (sdb2) — the one passphrase prompt at boot.
        "luks-d32cf077-59d1-4de7-92b9-7010b525e41a".device = "/dev/disk/by-uuid/d32cf077-59d1-4de7-92b9-7010b525e41a";
        # Swap (sdb3).
        "luks-697133b4-4e65-48b0-9077-b8b92df8b7b3".device = "/dev/disk/by-uuid/697133b4-4e65-48b0-9077-b8b92df8b7b3";
        # The data disk (sda1) is deliberately NOT here: it is unlocked with a
        # keyfile from the decrypted root (fileSystems."/data".encrypted below),
        # so it adds no prompt of its own at boot.
      };
    };
    # The machine runs VMs (kvm-intel was in the scanned hardware config).
    kernelModules = [ "kvm-intel" ];
  };

  fileSystems = {
    # Root: LUKS on sdb2, btrfs with /, /home and /nix subvolumes.
    "/" = {
      device = "/dev/mapper/luks-d32cf077-59d1-4de7-92b9-7010b525e41a";
      fsType = "btrfs";
      options = [ "noatime" ];
    };
    "/home" = {
      device = "/dev/mapper/luks-d32cf077-59d1-4de7-92b9-7010b525e41a";
      fsType = "btrfs";
      options = [ "subvol=home" "noatime" ];
    };
    "/nix" = {
      device = "/dev/mapper/luks-d32cf077-59d1-4de7-92b9-7010b525e41a";
      fsType = "btrfs";
      options = [ "subvol=nix" "noatime" ];
    };
    "/boot" = {
      device = "/dev/disk/by-uuid/F6D7-9514";
      fsType = "vfat";
      options = [ "fmask=0077" "dmask=0077" ];
    };
    # Second SATA SSD (2 TB), LUKS+btrfs — carries the Syncthing data tree.
    # Mounted at /data so the bind mount below can serve it at /sync.
    # Unlocked with a keyfile from the decrypted root (encrypted.keyFile):
    # with the scripted initrd the encrypted module adds a postMountCommand
    # that runs `cryptsetup luksOpen --key-file` once / is mounted under
    # /mnt-root, so this disk needs no passphrase prompt at boot.
    "/data" = {
      device = "/dev/mapper/data";
      fsType = "btrfs";
      options = [ "compress=zstd" "noatime" ];
      encrypted = {
        enable = true;
        blkDev = "/dev/disk/by-uuid/da463042-ab85-4999-979b-91f70c7c17a7";
        label = "data";
        keyFile = "/sysroot/root/.luks-keys/sda.key";
      };
    };
  };

  # LUKS-encrypted swap (sdb3).
  swapDevices = [ {
    device = "/dev/mapper/luks-697133b4-4e65-48b0-9077-b8b92df8b7b3";
  } ];

  networking.useDHCP = lib.mkDefault true;
  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";

  hardware = {
    cpu.intel.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
    graphics = {
      enable = true;
      enable32Bit = true;
    };
    nvidia = {
      # NVIDIA RTX 3060 12GB (Ampere GA106, compute capability 8.6)
      dynamicBoost.enable = false;
      gsp.enable = true;
      modesetting.enable = true;
      nvidiaSettings = true;
      # Proprietary modules. (NVIDIA recommends the open modules for Ampere;
      # the proprietary driver is fully supported there as well.)
      open = false;
      # package set in server-nike.nix to avoid duplicate definition
      powerManagement = {
        enable = false;
        finegrained = false;
      };
      prime = {
        # Single-GPU system: the RTX 3060 (Slot 1) is the only and display GPU.
        # The former GT 730 (Slot 3) was removed, so there is no dual-GPU offload.
        # Verified on the machine: 0000:01:00.0, 10de:2504 (GA106).
        nvidiaBusId = "PCI:1:0:0";
      };
      videoAcceleration = true;
    };
  };
}
