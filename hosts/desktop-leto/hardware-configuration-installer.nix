# This file was generated on desktop-leto (Gigabyte GA-B85-HD3, i7-4771)
# Run `sudo nixos-generate-config --show-hardware-config` and replace
# this file with the output after the first boot.

{ config, lib, pkgs, modulesPath, ... }:

{
  imports = [ (modulesPath + "/installer/scan/not-detected.nix") ];

  boot.initrd.availableKernelModules = [ "ata_piix" "ahci" "sd_mod" "sr_mod" ];
  boot.initrd.kernelModules = [ ];
  boot.kernelModules = [ ];
  boot.extraModulePackages = [ ];

  # UEFI boot (adjust to "legacy" if you chose Legacy/CSM mode in BIOS)
  fileSystems."/" = {
    device = "/dev/mapper/cryptroot";
    fsType = "btrfs";
    options = [ "compress=zstd" "noatime" "subvol=@" ];
  };

  fileSystems."/boot" = {
    device = "/dev/disk/by-uuid/<BOOT-UUID>";  # ← replace after first boot
    fsType = "vfat";
    options = [ "fmask=0077" "dmask=0077" ];
  };

  fileSystems."/home" = {
    device = "/dev/mapper/cryptroot";
    fsType = "btrfs";
    options = [ "compress=zstd" "noatime" "subvol=@home" ];
  };

  fileSystems."/nix" = {
    device = "/dev/mapper/cryptroot";
    fsType = "btrfs";
    options = [ "compress=zstd" "noatime" "subvol=@nix" ];
  };

  swapDevices = [
    { device = "/nix/swapfile"; }
  ];

  # Encrypted root
  boot.initrd.luks.devices."cryptroot" = {
    device = "/dev/disk/by-uuid/<LUKS-UUID>";  # ← replace after first boot
    allowDiscards = true;
  };

  networking.useDHCP = lib.mkDefault true;
  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
}
