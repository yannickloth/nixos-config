{ config, lib, pkgs, ... }:

with lib;
{
  imports =
  [
    # Include the results of the hardware scan.
      ./hardware-configuration.nix

      ../../roles/nix-gc.nix

      ../../environments/laptop.nix

      ../../hardware/intel_cpu.nix
      ../../hardware/intel_graphics.nix
      ../../hardware/thunderbolt.nix
      ../../hardware/printers/brother-mfcl2700dw.nix
      ../../hardware/printers/epson-xp15000.nix
      
      
      ../../roles/i18n/fr_BE.nix
      ../../apps/android.nix
      ../../apps/appimage.nix
      ../../services/avahi.nix
      ../../hardware/bluetooth.nix
      ../../services/clamav.nix
      ../../desktop/console.nix
      ../../hardware/corsair.nix
      ../../hardware/firmware.nix
      ../../apps/flatpak.nix
      ../../roles/fonts.nix
      ../../games/games.nix
      #../../desktop/gnome.nix
      #../../apps/go-scripting.nix
      ../../apps/gstreamer.nix
      ../../apps/java.nix
      #../../apps/jitsi-meet.nix
      #../../services/kubernetes.nix
      ../../services/libvirt.nix
      ../../services/network-manager.nix
      ../../roles/nix.nix
      ../../services/nix-serve.nix
      ../../services/onedrive.nix
      ../../services/openssh.nix
      ../../hardware/pcscd.nix
      ../../desktop/pipewire.nix
      ../../desktop/plasma.nix
      ../../services/plantuml.nix
      ../../services/podman.nix
      #../../services/postgresql.nix # containerized postgresql
      ../../services/printing.nix
      ../../apps/purescript.nix
      ../../services/samba.nix
      ../../services/scanning.nix
      ../../roles/shell.nix
      ../../services/sonos.nix
      ../../games/steam.nix
      ../../security/sudo.nix
      ../../services/tor.nix
      ../../security/tpm.nix
      ../../apps/typst.nix
      #../../services/virtualbox.nix
      ../../apps/waydroid.nix
      ../../desktop/xserver.nix
      ../../desktop/xwayland.nix
      ../../security/yubikey.nix

      ../../roles/base.nix

      ../../users/aeiuno/aeiuno-hm.nix
      ../../users/nicky/nicky-hm.nix
      ../../users/sven/sven-hm.nix
  ];
  # In this file comes everything that is specific to this host.
  networking.hostName = "laptop-xps"; # Define your hostname.

  # Bootloader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # Btrfs swapfile on the root filesystem (in addition to zram) as disk-swap overflow.
  swapDevices = [ { device = "/swapfile"; size = 16384; } ]; # 16 GiB; adjust to match RAM/disk

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

  nix.settings = {
    # cores = 0; # This option defines the maximum number of concurrent tasks during one build. It affects, e.g., -j option for make. The special value 0 means that the builder should use all available CPU cores in the system. Some builds may become non-deterministic with this option; use with care! Packages will only be affected if enableParallelBuilding is set for them.
    # max-jobs = 4; # This option defines the maximum number of jobs that Nix will try to build in parallel. The default is auto, which means it will use all available logical cores. It is recommend to set it to the total number of logical cores in your system (e.g., 16 for two CPUs with 4 cores each and hyper-threading).
    system-features = [
      "benchmark" # May apply to packages or tests that depend on benchmarking features.
      "big-parallel" # Enables tasks designed for builds that heavily leverage parallelism (> 16 cores), but enabling it on a system with a low core count (e.g., 4 logical cores) can lead to inefficiencies and potential issues:
      "cgroups" # Specifies that the system supports Linux cgroups (Control Groups), which are often used for resource isolation.
      "kvm" # Indicates that the system can perform builds inside a KVM virtual machine.
      "nixos" # Indicates that the system is running NixOS. This is automatically set on NixOS.
      "nixos-test" # It allows for automated tests of NixOS modules, configurations, and services in virtual machines or containers. Tests typically run within QEMU virtual machines (or other supported backends) that emulate a full NixOS system.
      "reproducible-paths" #     Ensures paths in builds are highly deterministic.
      "sandbox" # Indicates that builds should be sandboxed. A sandboxed build means that the environment is completely isolated and cannot access the host filesystem or network, ensuring purity in builds.
    ];
  };
}
