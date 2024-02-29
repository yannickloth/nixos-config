{ config, lib, pkgs, ... }:

with lib;
{
  imports =
  [
    # Include the results of the hardware scan.
      #<nixpkgs/nixos/modules/services/hardware/sane_extra_backends/brscan4.nix>
      #<home-manager/nixos>
      ./hardware-configuration.nix

      ../../nix-automatic-gc-7d.nix

      ../../environments/laptop.nix

      ../../hardware/intel_cpu.nix
      ../../hardware/intel_graphics.nix
      ../../hardware/thunderbolt.nix
      
      ../../modules/xpad.nix
      
      ../../profiles/i18n/fr_BE.nix
      ../../profiles/android.nix
      ../../profiles/avahi.nix
      ../../profiles/bluetooth.nix
      ../../profiles/clamav.nix
      #../../profiles/corsair.nix
      ../../profiles/firmware.nix
      ../../profiles/flatpak.nix
      ../../profiles/gnome.nix
      ../../profiles/gstreamer.nix
      ../../profiles/java.nix
      ../../profiles/jitsi-meet.nix
      ../../profiles/libvirt.nix
      ../../profiles/network-manager.nix
      ../../profiles/nix.nix
      ../../profiles/onedrive.nix
      ../../profiles/openssh.nix
      ../../profiles/pcscd.nix
      ../../profiles/pipewire.nix
      ../../profiles/plantuml.nix
      ../../profiles/podman.nix
      #../../profiles/postgresql.nix # containerized postgresql
      ../../profiles/printing.nix
      ../../profiles/purescript.nix
      ../../profiles/samba.nix
      ../../profiles/scanning.nix
      ../../profiles/shell.nix
      ../../profiles/sonos.nix
      ../../profiles/steam.nix
      ../../profiles/tor.nix
      #../../profiles/virtualbox.nix
      ../../profiles/waydroid.nix
      ../../profiles/xserver.nix
      ../../profiles/xwayland.nix
      ../../profiles/yubikey.nix

      ../../roles/base.nix

      ../../users/aeiuno/aeiuno-hm.nix
      ../../users/nicky/nicky-hm.nix
  ];
  # In this file comes everything that is specific to this host.
  networking.hostName = "laptop-hera"; # Define your hostname.

  # Bootloader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
}
