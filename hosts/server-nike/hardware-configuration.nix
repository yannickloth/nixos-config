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
#   - sda (1.8T): LUKS data disk (btrfs) at /data, unlocked in the initrd
#     with the same passphrase as root (boot.initrd.luks.reusePassphrases)
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
    ] ++ [
      # Open NVIDIA modules must own the device; nouveau must not bind.
      "nouveau"
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
      luks = {
        # One passphrase at boot unlocks all three containers. systemd
        # stage 1 mechanism: systemd-cryptsetup caches the typed passphrase
        # in the kernel keyring (crypttab option password-cache, default
        # yes) and the other devices pick it up before prompting, so boot
        # needs a single passphrase input. Requires the SAME passphrase on
        # root, swap and data — enforce that during the reinstall (see
        # zeplan.md §4.3). (reusePassphrases only applies to the legacy
        # scripted stage 1; it asserts here.)
        devices = {
          # Root disk (sdb2) — the one passphrase prompt at boot.
          "luks-e7d37111-6eee-4fdb-b2ab-63700afa9a36".device = "/dev/disk/by-uuid/e7d37111-6eee-4fdb-b2ab-63700afa9a36";
          # Swap (sdb3) — unlocked with the reused passphrase.
          "luks-386fd088-dcd0-4d51-a60c-71cb8dafa56f".device = "/dev/disk/by-uuid/386fd088-dcd0-4d51-a60c-71cb8dafa56f";
          # Data disk (sda1) — unlocked with the reused passphrase, so boot
          # needs exactly one prompt. No keyfile in the boot path; the
          # keyfile slot in the LUKS header stays as an offline recovery
          # path (zeplan.md §4.4).
          data.device = "/dev/disk/by-uuid/da463042-ab85-4999-979b-91f70c7c17a7";
        };
      };
    };
    # The machine runs VMs (kvm-intel was in the scanned hardware config).
    kernelModules = [ "kvm-intel" ];
  };

  fileSystems = {
    # Root: LUKS on sdb2, btrfs with /, /home and /nix subvolumes.
    "/" = {
      device = "/dev/mapper/luks-e7d37111-6eee-4fdb-b2ab-63700afa9a36";
      fsType = "btrfs";
      options = [ "noatime" ];
    };
    "/home" = {
      device = "/dev/mapper/luks-e7d37111-6eee-4fdb-b2ab-63700afa9a36";
      fsType = "btrfs";
      options = [ "subvol=home" "noatime" ];
    };
    "/nix" = {
      device = "/dev/mapper/luks-e7d37111-6eee-4fdb-b2ab-63700afa9a36";
      fsType = "btrfs";
      options = [ "subvol=nix" "noatime" ];
    };
    "/boot" = {
      device = "/dev/disk/by-uuid/69CA-7A5D";
      fsType = "vfat";
      options = [ "fmask=0077" "dmask=0077" ];
    };
    # Second SATA SSD (2 TB), LUKS+btrfs — carries the Syncthing data tree.
    # Mounted at /data so the bind mount below can serve it at /sync.
    # The LUKS container is opened in the initrd (boot.initrd.luks.devices
    # above) with the reused root passphrase, so the mapper device exists
    # before the real root is mounted and no keyfile or second prompt is
    # involved.
    "/data" = {
      device = "/dev/mapper/data";
      fsType = "btrfs";
      options = [ "compress=zstd" "noatime" ];
    };
  };

  # LUKS-encrypted swap (sdb3).
  swapDevices = [ {
    device = "/dev/mapper/luks-386fd088-dcd0-4d51-a60c-71cb8dafa56f";
  } ];

  networking.useDHCP = lib.mkDefault true;
  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
  # Open NVIDIA kernel modules need DRM modesetting enabled at kernel boot
  # level; nixpkgs sets this when hardware.nvidia.modesetting.enable = true,
  # but being explicit guarantees it survives any future nixpkgs refactor.
  boot.kernelParams = [ "nvidia-drm.modeset=1" ];

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
      # `open` and `package` come from hardware/nvidia_ampere.nix: proprietary
      # modules, because the open modules spin kwin_wayland and kmscon on the
      # KMS/DRM paths of this card.
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
