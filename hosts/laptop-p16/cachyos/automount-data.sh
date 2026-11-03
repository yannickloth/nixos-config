#!/bin/sh
# Unlock and mount /data automatically on laptop-p16.
#
# Why: /data is its own LUKS volume (nvme0n1p1) with a btrfs filesystem on top.
# Its mount is in /etc/fstab with `nofail`, but nothing opens the LUKS container
# at boot, so the mapper never appears, the mount is skipped, and the volume
# only comes back after a manual `cryptsetup open` + `mount` with the
# passphrase. That is fine for a Steam library; it is not fine for
# ~/.config/containers/storage.conf, which points podman's graphroot at
# /data/containers/nicky (packages/unsloth-studio/container.nix): podman then
# fails for every command until the volume is up.
#
# What this installs (full mode, i.e. CachyOS):
#   1. a random keyfile at /etc/luks/data.key (mode 0400, root-only), enrolled
#      as an additional LUKS key — the existing passphrase slot stays valid as
#      the recovery path;
#   2. an /etc/crypttab line so systemd-cryptsetup unlocks it at boot, which
#      makes the existing /etc/fstab line mount it;
#   3. `x-systemd.automount` on that fstab line, so a later unlock (or a slow
#      one) still resolves on first access instead of leaving an empty /data.
#
# Key mode (`--key-only`) does step 1 and nothing else. That is the mode a
# NixOS install needs: /etc/crypttab and /etc/fstab there are generated from
# hosts/laptop-p16/data-volume.nix, and only the key enrolment is not
# declarative. The script selects key mode by itself when it finds /etc/NIXOS.
#
# Run with sudo. Idempotent: a second run finds every piece in place and only
# re-checks them. Verify with:
#
#   systemctl status data.automount data.mount
#   df -h /data
set -eu

[ "$(id -u)" -eq 0 ] || { echo "run with sudo" >&2; exit 1; }

mode=full
case "${1:-}" in
  --key-only) mode=key ;;
  "") ;;
  *) echo "usage: $0 [--key-only]" >&2; exit 2 ;;
esac
if [ -e /etc/NIXOS ]; then
  [ "$mode" = key ] || echo "NixOS detected: only the LUKS key is managed here; crypttab and fstab come from hosts/laptop-p16/data-volume.nix."
  mode=key
fi

# The btrfs filesystem (as referenced by /etc/fstab) and its LUKS container.
fs_uuid=fbaa1e9e-a163-43f7-9ea7-a3ba564e061b
luks_uuid=bfece090-af9c-4962-89e9-061d799cf864
mapper="luks-$luks_uuid"
key=/etc/luks/data.key

dev=$(blkid -t UUID="$luks_uuid" -o device | head -1)
[ -n "$dev" ] || { echo "no LUKS device with UUID $luks_uuid" >&2; exit 1; }
echo "LUKS device for /data: $dev ($mapper)"

# 1. keyfile
install -d -m 0700 /etc/luks
if [ ! -f "$key" ]; then
  ( umask 077; dd if=/dev/urandom of="$key" bs=64 count=1 2>/dev/null )
  chmod 0400 "$key"
  echo "created $key"
fi

# Enrol only when the key is not already a slot: --test-passphrase asks LUKS to
# try it without unlocking anything.
if cryptsetup open --test-passphrase --key-file "$key" "$dev" 2>/dev/null; then
  echo "$key is already enrolled"
else
  echo "enrolling $key as an additional LUKS key (enter the existing passphrase once):"
  cryptsetup luksAddKey "$dev" "$key"
fi

if [ "$mode" = key ]; then
  printf '%s\n' \
    "done (key only)." \
    "crypttab + fstab automount must come from hosts/laptop-p16/data-volume.nix (NixOS)." \
    "The keyfile stays at $key; keep the passphrase slot as the recovery path."
  exit 0
fi

# 2. crypttab. Match on the UUID, not the mapper name, so a hand-written line
#    with a different name is not duplicated.
if grep -qs "$luks_uuid" /etc/crypttab; then
  echo "/etc/crypttab already has $luks_uuid"
else
  printf '%s UUID=%s %s luks,discard,nofail\n' "$mapper" "$luks_uuid" "$key" >> /etc/crypttab
  chmod 0600 /etc/crypttab
  echo "added $mapper to /etc/crypttab"
fi

# 3. automount flags on the existing /data line (device stays `UUID=<fs>`).
if grep -qs "^UUID=$fs_uuid.*x-systemd.automount" /etc/fstab; then
  echo "/etc/fstab already automounts /data"
else
  sed -i "s|^UUID=$fs_uuid\(.*\)nofail|UUID=$fs_uuid\1nofail,x-systemd.automount,x-systemd.device-timeout=10s|" /etc/fstab
  grep -qs "^UUID=$fs_uuid.*x-systemd.automount" /etc/fstab \
    || { echo "could not rewrite the /data line in /etc/fstab; edit it by hand" >&2; exit 1; }
  echo "enabled automount for /data in /etc/fstab"
fi

systemctl daemon-reload
# If the volume is already open and mounted, this only re-reads the units; the
# automount takes over at the next boot.
systemctl start data.automount 2>/dev/null || true

if [ -e "/dev/mapper/$mapper" ] && ! mountpoint -q /data; then
  systemctl start data.mount || true
fi

printf '%s\n' \
  "done." \
  "At the next boot systemd-cryptsetup unlocks /data with $key and fstab mounts it." \
  "Check now:  systemctl status data.automount data.mount; df -h /data"
