# Shared module set for every family laptop (laptop-hera, laptop-p16,
# laptop-xps).
#
# IVP: these 53 modules have the same change-driver set
# {D-SERVICE, D-APP, D-DESKTOP, D-HARDWARE, D-SECURITY, D-SYSTEM} — they change
# when a service/app/desktop-stack/peripheral/security/base policy changes, not
# when a *host* changes. They used to be copy-pasted into each host file (and
# had already drifted), so they live here now.
#
# Host-specific modules (kernel choice, per-host apps, RAM-dependent settings,
# the home-manager user wiring) stay in hosts/<host>/<host>.nix. Current deltas:
#   laptop-hera: apps/benchmark.nix
#   laptop-p16:  apps/benchmark.nix, apps/obs-studio.nix, apps/wine.nix
#                (services/immich.nix exists but is commented out while p16 runs
#                 CachyOS; the server runs via home-manager there)
#   laptop-xps: apps/noson.nix, desktop/plasma.nix
{ ... }:

{
  imports = [
    # Laptop environment (power management, zram, thermald, timezone) and its
    # firewall (nftables + nix-serve Tailscale rule).
    ./laptop.nix

    # Apps / language toolchains.
    ../apps/android.nix
    ../apps/appimage.nix
    ../apps/flatpak.nix
    ../apps/gstreamer.nix
    ../apps/java.nix
    ../apps/kdeconnect.nix
    ../apps/purescript.nix
    ../apps/typst.nix
    ../apps/waydroid.nix

    # Desktop / display / audio.
    ../desktop/console.nix
    ../desktop/hyprland.nix
    ../desktop/pipewire.nix
    ../desktop/xserver.nix
    ../desktop/xwayland.nix

    # Games.
    ../games/games.nix
    ../games/steam.nix

    # Hardware.
    ../hardware/bluetooth.nix
    ../hardware/firmware.nix
    ../hardware/intel_cpu.nix
    ../hardware/intel_graphics.nix
    ../hardware/pcscd.nix
    ../hardware/printers/brother-mfcl2700dw.nix
    ../hardware/printers/epson-xp15000.nix
    ../hardware/thunderbolt.nix

    # Roles / base policy.
    ../roles/base.nix
    ../roles/bees.nix
    ../roles/fonts.nix
    ../roles/i18n/fr_BE.nix
    ../roles/nix-gc.nix
    ../roles/psd.nix
    ../roles/shell.nix

    # Security.
    ../security/apparmor.nix
    ../security/sudo.nix
    ../security/tpm.nix
    ../security/yubikey.nix

    # Services.
    ../services/ai-chat.nix
    ../services/avahi.nix
    ../services/clamav.nix
    ../services/libvirt.nix
    ../services/malcontent.nix
    ../services/network-manager.nix
    ../services/nix-serve.nix
    ../services/openssh.nix
    ../services/plantuml.nix
    ../services/podman.nix
    ../services/printing.nix
    ../services/samba.nix
    ../services/scanning.nix
    ../services/sonos.nix
    ../services/syncthing
    ../services/tor.nix
  ];
}
