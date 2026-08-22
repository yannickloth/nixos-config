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
      ../../services/bittorrent.nix
      ../../apps/benchmark.nix
      ../../hardware/bluetooth.nix
      ../../services/clamav.nix
      ../../desktop/console.nix
      ../../hardware/corsair.nix
      ../../hardware/firmware.nix
      ../../apps/flatpak.nix
      ../../roles/fonts.nix
      ../../games/games.nix
      #../../desktop/gnome.nix
      ../../apps/gstreamer.nix
      ../../apps/java.nix
      #../../apps/jitsi-meet.nix
      ../../services/libvirt.nix
      ../../services/malcontent.nix
      ../../services/network-manager.nix
      ../../services/nix-serve.nix
      ../../services/onedrive.nix
      ../../services/openssh.nix
      ../../hardware/pcscd.nix
      ../../desktop/pipewire.nix
      ../../services/plantuml.nix
      ../../services/podman.nix
      #../../services/postgresql.nix # containerized postgresql
      ../../services/printing.nix
      ../../apps/purescript.nix
      ../../services/samba.nix
      ../../services/scanning.nix
      ../../services/syncthing.nix
      ../../roles/shell.nix
      ../../services/sonos.nix
      ../../games/steam.nix
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
  networking.hostName = "laptop-hera"; # Define your hostname.

  # 64 GiB RAM -> run browser profiles in RAM.
  roles.psd.enable = true;

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
