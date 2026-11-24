# Shared module set for every family host: laptop-hera, laptop-p16,
# laptop-xps, desktop-leto and server-nike. Chassis-independent family policy.
#
# IVP: these modules have the same change-driver set
# {D-SERVICE, D-APP, D-DESKTOP, D-HARDWARE, D-SECURITY, D-SYSTEM} — they change
# when a service/app/desktop-stack/peripheral/security/base policy changes, not
# when a *host* or a *chassis* changes.
#
# Split (2026-11-24, out of the former family-laptop monolith):
#   - family-host.nix (this file): everything every family machine gets.
#     server-nike — a tower used daily as a desktop, with an RTX 3060 and no
#     iGPU — imports it directly, so its desktop/service policy stays identical
#     to laptop-p16's by construction.
#   - family-laptop.nix: family-host + the portable-chassis layer
#     (environments/laptop.nix power management + nftables firewall) and the
#     Intel iGPU VA-API stack, which only hosts with an iGPU may load (it
#     mkForces hardware.graphics.extraPackages to the Intel media drivers).
#
# Timezone: roles/base.nix defaults to Europe/Luxembourg; no environment pins
# its own — one source, no mkForce arms race.
{ lib, ... }:

{
  imports = [
    # Roles / base policy.
    ../roles/base.nix
    ../roles/bees.nix
    ../roles/fonts.nix
    ../roles/i18n/fr_BE.nix
    ../roles/nix-gc.nix
    ../roles/psd.nix
    ../roles/shell.nix

    # Desktop / display / audio.
    ../desktop/console.nix
    ../desktop/pipewire.nix
    ../desktop/xserver.nix
    ../desktop/xwayland.nix

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

    # Games.
    ../games/games.nix
    ../games/steam.nix

    # Hardware.
    ../hardware/bluetooth.nix
    ../hardware/firmware.nix
    ../hardware/intel_cpu.nix
    ../hardware/pcscd.nix
    ../hardware/printers/brother-mfcl2700dw.nix
    ../hardware/printers/epson-xp15000.nix
    ../hardware/thunderbolt.nix

    # Security.
    ../security/apparmor.nix
    ../security/sudo.nix
    ../security/tpm.nix
    ../security/yubikey.nix

    # Services.
    ../services/avahi.nix
    ../services/xrdp.nix
    ../services/clamav.nix
    ../services/libvirt.nix
    ../services/malcontent.nix
    ../services/network-manager.nix
    ../services/nix-serve.nix
    ../services/openssh.nix
    ../services/plantuml.nix
    ../services/podman.nix
    ../services/postgresql.nix
    ../services/printing.nix
    ../services/samba.nix
    ../services/scanning.nix
    ../services/sonos.nix
    ../services/ssh-user-keys.nix
    ../services/syncthing
    ../services/tor.nix
  ];

  # Distribute the family SSH identities + authorized_keys on every host
  # (see services/ssh-user-keys.nix). Not chassis-specific: desktop-leto and
  # server-nike get them too.
  services.sshUserKeys.enable = true;

  # xRDP — allows concurrent X11 sessions on virtual displays while the
  # physical console stays on Wayland/KWin.  Every host gets both the server
  # (services/xrdp.nix) and the client (krdc in roles/system.nix) so that
  # every machine can be remotely accessed from any other.
  services.xrdp.enable = true;

  # Flatpak apps installed per-user that malcontent's allowlist gates for the
  # kids (malcontent only filters flatpak apps; it filters per-user apps by
  # app id just like system ones). Kept in sync with the allowlist in
  # services/malcontent.nix. Browsers stay in Nix: Firefox needs its
  # declarative kid policies (users/kid-firefox-policies.nix). The kids'
  # office/creative/media/mail/games apps (libreoffice, gimp, krita, VLC,
  # Geary, the KDE mini-games) come from flatpak so malcontent can gate them
  # without a Nix rebuild, while adults get those apps natively via
  # home-manager — one source per user, never native + flatpak both.
  # Overrides grant access to the shared family drop folder (/filedrop).
  # The kids' file manager (Dolphin) is native, not flatpak: it needs
  # group/ACL access to /filedrop (filedrop group), which a sandboxed
  # flatpak can't use — see the rule of thumb in users/readmes/parents.md.
  # adultApps is the same list minus the apps nicky/aeiuno already have from
  # Nixpkgs (gimp, krita, libreoffice, vlc, obsidian, dolphin, gwenview,
  # kalk, okular, calibre, filelight), so the adults never end up with two
  # copies of an app.
  # Note: KDE's Minesweeper is org.kde.kmines on Flathub (org.kde.Mines is a
  # nonexistent id), and replaces GNOME Mines (removed: duplicates kmines).
  # Every id below MUST resolve on flathub, or the whole per-user install unit
  # fails and skips the apps after it. Two were wrong and are now fixed:
  #   - org.gnome.Clocks -> org.gnome.clocks (Flathub uses the lowercase id)
  #   - org.gnome.SystemMonitor -> removed, it is not on Flathub at all
  #     (`flatpak remote-info flathub org.gnome.SystemMonitor` shows no ref).
  #     It was a default desktop tool rather than a gated kids' app; add it
  #     natively to home-manager (pkgs.gnome-system-monitor) if wanted.
  # Check a new id with: flatpak remote-info flathub app/<id>/x86_64/stable
  #
  # Lives here (not in roles/base.nix) because the apps.flatpak option is
  # defined by apps/flatpak.nix, which family-host.nix imports — every family
  # host (server-nike included) therefore has the option.
  apps.flatpak = {
    enable = lib.mkDefault true;
    apps = [
      "app/org.gnome.Cheese/x86_64/stable"
      "app/org.gnome.clocks/x86_64/stable"
      "app/org.gnome.Geary/x86_64/stable"
      "app/org.gnome.Logs/x86_64/stable"
      "app/org.gnome.Maps/x86_64/stable"
      "app/org.gnome.Nibbles/x86_64/stable"
      "app/org.gnome.Chess/x86_64/stable"
      "app/org.atheme.audacious/x86_64/stable"
      "app/org.kde.granatier/x86_64/stable"
      "app/org.kde.gwenview/x86_64/stable"
      "app/org.kde.kalk/x86_64/stable"
      "app/org.kde.katomic/x86_64/stable"
      "app/org.kde.kblocks/x86_64/stable"
      "app/org.kde.kbreakout/x86_64/stable"
      "app/org.kde.kdiamond/x86_64/stable"
      "app/org.kde.kmahjongg/x86_64/stable"
      "app/org.kde.kmines/x86_64/stable"
      "app/org.kde.kpat/x86_64/stable"
      "app/org.kde.kshisen/x86_64/stable"
      "app/org.kde.ksudoku/x86_64/stable"
      "app/org.kde.krita/x86_64/stable"
      "app/org.kde.kwordquiz/x86_64/stable"
      "app/org.kde.khangman/x86_64/stable"
      "app/org.kde.kanagram/x86_64/stable"
      "app/org.kde.kturtle/x86_64/stable"
      "app/org.kde.kgeography/x86_64/stable"
      "app/org.kde.kalgebra/x86_64/stable"
      "app/org.kde.kig/x86_64/stable"
      "app/org.kde.kstars/x86_64/stable"
      "app/org.kde.okular/x86_64/stable"
      "app/org.kde.filelight/x86_64/stable"
      "app/org.gimp.GIMP/x86_64/stable"
      "app/com.calibre_ebook.calibre/x86_64/stable"
      "app/org.libreoffice.LibreOffice/x86_64/stable"
      "app/org.videolan.VLC/x86_64/stable"
      "app/md.obsidian.Obsidian/x86_64/stable"
      "app/org.stellarium.Stellarium/x86_64/stable"
      "app/edu.mit.Scratch/x86_64/stable"
      "app/io.gdevelop.ide/x86_64/stable"
      "app/org.geogebra.GeoGebra/x86_64/stable"
    ];
    adultApps = [
      "app/org.gnome.Cheese/x86_64/stable"
      "app/org.gnome.clocks/x86_64/stable"
      "app/org.gnome.Geary/x86_64/stable"
      "app/org.gnome.Logs/x86_64/stable"
      "app/org.gnome.Maps/x86_64/stable"
      "app/org.stellarium.Stellarium/x86_64/stable"
    ];
    overrides = {
      "org.kde.krita" = [ "--filesystem=/filedrop" ];
      "org.gimp.GIMP" = [ "--filesystem=/filedrop" ];
      "org.libreoffice.LibreOffice" = [ "--filesystem=/filedrop" ];
      "org.videolan.VLC" = [ "--filesystem=/filedrop" ];
      "md.obsidian.Obsidian" = [ "--filesystem=/filedrop" ];
    };
  };

  # /data is a separate LUKS+btrfs volume on laptop-p16, laptop-hera and
  # server-nike. On the hosts without a second drive (laptop-xps, desktop-leto)
  # these rules create /data itself as a plain root-disk directory, so their
  # data is not encrypted at rest; tmpfiles creates the leading dir as root and
  # the subdirs below as the appropriate user. "d" only creates what is
  # missing, so server-nike's own stricter modes (2770 for the sync/containers
  # dirs, set by its host unit) are never overwritten.
  systemd.tmpfiles.rules = [
    "d /data 0755 root root -"                       # root-FS dir on xps/leto; mount point on hera/p16/nike
    "d /data/postgres 0750 postgres postgres -"       # PostgreSQL 18 cluster
    "d /data/unsloth 0700 nicky nicky -"              # Unsloth Studio model data
    "d /data/containers 0755 nicky nicky -"           # Podman graphroot
  ];
}
