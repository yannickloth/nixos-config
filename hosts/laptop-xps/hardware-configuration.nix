# Do not modify this file!  It was generated by ‘nixos-generate-config’
# and may be overwritten by future invocations.  Please make changes
# to /etc/nixos/configuration.nix instead.
{ config, lib, pkgs, modulesPath, ... }:

{
  # To import nixos-hardware, first add the corresponding channel
  # $ sudo nix-channel --add https://github.com/NixOS/nixos-hardware/archive/master.tar.gz nixos-hardware
  # $ sudo nix-channel --update
  imports =
    [ (modulesPath + "/installer/scan/not-detected.nix")
      #<nixos-hardware/dell/xps/13-9360>
    ];
  boot = {
    blacklistedKernelModules = [ "psmouse" ] ++ lib.optionals (!config.hardware.enableRedistributableFirmware) [ "ath3k" ];
    initrd = {
      availableKernelModules = [ "xhci_pci" "nvme" "usb_storage" "sd_mod" "rtsx_pci_sdmmc" ];
      kernelModules = [ "aesni_intel" "cryptd" "i915" ];
      luks = {
        reusePassphrases = true;
        devices."root".device = "/dev/disk/by-uuid/5641cc65-6819-487c-81d7-05b039dfd58d";
        devices.luks_swap.device = "/dev/disk/by-uuid/0fac828e-7388-4ce7-8d7d-3713c40d1e75"; # encrypted swap partition
      };
    };
    kernelModules = [ "kvm-intel" "iwlwifi"];
    kernelParams = [
      "i915.enable_fbc=1"
      "i915.enable_psr=2"
    ];
    kernel.sysctl = { "vm.swappiness" = 10; "fs.inotify.max_user_watches" = 2097152; };
  };
  fileSystems."/" =
    { device = "/dev/disk/by-uuid/9836344f-337f-459c-8c97-e39f7caff437";
      fsType = "btrfs";
      options = [ "compress=zstd" "subvol=@" ];
    };



  fileSystems."/boot" =
    { device = "/dev/disk/by-uuid/D1D6-F3A0";
      fsType = "vfat";
    };

  swapDevices =
    [
      {
        device = "/dev/disk/by-uuid/8d6f5055-5eb6-42eb-a93e-b5b481d0aa1c";
        encrypted = {
          enable = true;
          label = "luks_swap";
          blkDev = "/dev/disk/by-uuid/0fac828e-7388-4ce7-8d7d-3713c40d1e75"; # encrypted swap partition
        };
      }
    ];

  # Enables DHCP on each ethernet and wireless interface. In case of scripted networking
  # (the default) this is the recommended approach. When using systemd-networkd it's
  # still possible to use this option, but it's recommended to use it in conjunction
  # with explicit per-interface declarations with `networking.interfaces.<interface>.useDHCP`.
  networking.useDHCP = lib.mkDefault true;
  # networking.interfaces.wlp58s0.useDHCP = lib.mkDefault true;

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
  powerManagement.cpuFreqGovernor = lib.mkDefault "powersave";
  hardware.cpu.intel.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
  environment.variables = {
    VDPAU_DRIVER = lib.mkIf config.hardware.opengl.enable (lib.mkDefault "va_gl");
  };
  hardware.opengl.extraPackages = with pkgs; [
    (if (lib.versionOlder (lib.versions.majorMinor lib.version) "23.11") then vaapiIntel else intel-vaapi-driver)
    libvdpau-va-gl
    intel-media-driver
  ];
  # This will save you money and possibly your life!
  services.thermald.enable = true;

}
