# FHS compatibility symlinks for applications that do their own filesystem
# probing instead of using fontconfig / XDG_DATA_DIRS.
#
# The ArtCraft "Crafting Apps" are the main driver: they embed fontdb-style
# font enumeration and hard-code traditional FHS paths for dictionaries,
# timezone data, gsettings, icons, etc. NixOS keeps those resources under
# /run/current-system/sw/share or /etc, so the apps only find what they embed
# or what lives in ~/.local/share. This module bridges the gap by symlinking
# the FHS locations those apps expect to the NixOS equivalents.
#
# This is intentionally a small, explicit list: add a symlink here only when a
# real application is observed to need it (grep its binary for /usr/share,
# /usr/bin, /etc paths), not as a wholesale FHS re-creation.

{ pkgs, ... }:

{
  systemd.tmpfiles.rules = [
    # Spell-check dictionaries (WordCraft/DeckCraft/DesignCraft). The hunspell
    # and myspell dictionaries are installed system-wide in roles/system.nix.
    "L+ /usr/share/hunspell         - - - - /run/current-system/sw/share/hunspell"
    "L+ /usr/share/myspell/dicts    - - - - /run/current-system/sw/share/myspell/dicts"

    # Timezone database. NixOS exposes it through /etc/zoneinfo; many Rust
    # timezone crates and office apps first look at /usr/share/zoneinfo.
    "L+ /usr/share/zoneinfo         - - - - /etc/zoneinfo"

    # gsettings is used by some apps to read portal/desktop settings (dark
    # mode, scaling). It lives in glib's bin output, not on a global FHS path.
    "L+ /usr/bin/gsettings          - - - - ${pkgs.glib.bin}/bin/gsettings"

    # ldconfig is sometimes shelled out to enumerate installed libraries
    # (/sbin/ldconfig exists on NixOS, but some apps hard-code /usr/sbin/ldconfig).
    "L+ /usr/sbin/ldconfig          - - - - ${pkgs.glibc.bin}/bin/ldconfig"

    # Icon and pixmap directories. Most toolkits use XDG_DATA_DIRS, but
    # hard-coded /usr/share/{icons,pixmaps} probes are common in app-specific
    # code (e.g. cursor/icon fallbacks in the Craft apps).
    "L+ /usr/share/icons            - - - - /run/current-system/sw/share/icons"
    "L+ /usr/share/pixmaps          - - - - /run/current-system/sw/share/pixmaps"
  ];
}
