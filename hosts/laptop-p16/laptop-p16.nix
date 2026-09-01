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
      ../../apps/kdeconnect.nix
      ../../services/libvirt.nix
      ../../services/malcontent.nix
      ../../services/network-manager.nix
      ../../services/nix-serve.nix
      ../../apps/obs-studio.nix
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
      ../../services/syncthing
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
      ../../apps/wine.nix
      ../../desktop/xserver.nix
      ../../desktop/xwayland.nix
      ../../security/yubikey.nix

      ../../roles/base.nix
      ../../roles/psd.nix

      # commonHm.hostName tells the home-manager modules which host they target.
      # config.networking.hostName is NOT reachable inside home-manager modules
      # (they have their own config namespace), so this must be passed here.
      { home-manager.users.aeiuno = {
          imports = [ ../../users/aeiuno/aeiuno-hm.nix ];
          commonHm.hostName = "laptop-p16";
        }; }
      { home-manager.users.nicky = {
          imports = [ ../../users/nicky/nicky-hm.nix ];
          commonHm.hostName = "laptop-p16";
        }; }
      { home-manager.users.sven = {
          imports = [ ../../users/sven/sven-hm.nix ];
          commonHm.hostName = "laptop-p16";
        }; }
      { home-manager.users.aaron = {
          imports = [ ../../users/aaron/aaron-hm.nix ];
          commonHm.hostName = "laptop-p16";
        }; }
    ];
  # In this file comes everything that is specific to this host.
  networking.hostName = "laptop-p16"; # Define your hostname.

  # Syncthing device name for this host (see services/syncthing/pool.nix).
  services.syncthing.self = "laptop-p16";

  # 128 GiB RAM -> run browser profiles in RAM.
  roles.psd.enable = true;

  # Bootloader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # 128 GiB RAM -> parallel builds with all cores.
  roles.nix.maxJobs = 12;
  roles.nix.cores = 0;
}
