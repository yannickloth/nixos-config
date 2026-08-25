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
      ../../services/ai-chat.nix
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
      ../../apps/kdeconnect.nix
      ../../apps/noson.nix
      #../../services/kubernetes.nix
      ../../services/libvirt.nix
      ../../services/malcontent.nix
      ../../services/network-manager.nix
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
      ../../services/syncthing
      ../../security/apparmor.nix
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
      ../../roles/psd.nix

      { home-manager.users.aeiuno = import ../../users/aeiuno/aeiuno-hm.nix; }
      { home-manager.users.nicky = import ../../users/nicky/nicky-hm.nix; }
      { home-manager.users.sven = import ../../users/sven/sven-hm.nix; }
      { home-manager.users.aaron = import ../../users/aaron/aaron-hm.nix; }
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
