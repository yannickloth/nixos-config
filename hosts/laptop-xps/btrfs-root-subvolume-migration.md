# laptop-xps — migrate `/` from the btrfs top level to `subvol=@`

## Why

`hosts/laptop-xps/hardware-configuration.nix` currently mounts the btrfs **top
level** (subvolume ID 5) at `/` (`subvol=@` is commented out), while `/home` and
`/nix` are separate subvolumes. Consequences:

- The top-level subvolume cannot be snapshotted → **no root rollback**.
- Other subvolumes (`/home`, `/nix`, the legacy `steamlib`) appear as plain
  directories in the `/` tree. If one fails to mount, its empty directory is
  silently used instead (e.g. an empty `/nix` at boot).
- A "system snapshot" of `/` is all-or-nothing and includes `/etc`, `/var`,
  `/srv`, `/opt` — or is impossible, depending on the tool.

Target layout (same as laptop-hera/p16):

```
/dev/mapper/luks-45c077f9-…  (btrfs top level, subvolid=5)
├── @        → /        (subvol=@, compress=zstd, noatime)
├── home     → /home    (subvol=home)          ← unchanged
├── nix      → /nix     (subvol=nix)           ← unchanged
└── steamlib              (legacy, delete later)
```

LUKS UUID of the root filesystem: `45c077f9-a627-4815-9a19-a1d6e33cb7c7`.
Bootloader: systemd-boot.

> **Read the whole procedure before starting.** The critical constraint: the
> running system mounts the top level, so as soon as the files move into `@`
> the *old* boot entries point at an empty root. The new generation (with
> `subvol=@`) must be built **before** the move, and the machine must not be
> rebooted normally between building it and booting the live ISO.

## 0. Preconditions

1. Back up what you cannot lose: at minimum `/etc` and `/var/lib` (Syncthing
   identity, container state, AccountsService). A full disk image is better:
   `sudo dd if=/dev/nvme0n1 of=/path/to/xps.img bs=64M status=progress` (on an
   external disk), or a `btrfs send` of `@home`.
2. Check free space in the filesystem:

   ```bash
   sudo btrfs filesystem usage /
   # size of everything that will be copied (excludes the subvolumes):
   sudo du -sh --exclude=/home --exclude=/nix --exclude=/proc --exclude=/sys \
     --exclude=/dev --exclude=/run /
   ```

   Copying (recommended, see step 3) needs that much **free** space on top of
   the current usage, because the originals are kept until the first successful
   boot. If space is tight, use the `mv` variant instead (single copy, no
   fallback).
3. Have a NixOS live ISO (any recent one) on a USB stick.

## 1. Build the new generation (on the running system)

Edit `hosts/laptop-xps/hardware-configuration.nix` and enable the subvolume for
`/`:

```nix
  fileSystems."/" =
    {
      device = "/dev/mapper/luks-45c077f9-a627-4815-9a19-a1d6e33cb7c7";
      fsType = "btrfs";
      options = [ "subvol=@" "compress=zstd" "noatime" ];
    };
```

Then build the generation **without switching** to it now:

```bash
cd /etc/nixos
sudo nixos-rebuild boot --flake /etc/nixos
sudo nix-env -p /nix/var/nix/profiles/system --list-generations | tail -n 3
```

Make a note of the new generation number. **Do not reboot into it yet** — `@`
does not exist until step 3, so that generation would boot with an empty `/`.
The next boot must be the live ISO.

## 2. Boot the live ISO and prepare

1. Boot the ISO. While in the desktop/console, note which disk holds the LUKS
   container (usually `/dev/nvme0n1p2` on the XPS):

   ```bash
   lsblk -f
   sudo cryptsetup luksUUID /dev/nvme0n1p2   # must print 45c077f9-a627-…
   ```

2. Open the LUKS container and mount the **top level**:

   ```bash
   sudo cryptsetup open /dev/nvme0n1p2 xpsroot
   sudo mkdir -p /mnt/btrfs
   sudo mount -t btrfs -o subvolid=5 /dev/mapper/xpsroot /mnt/btrfs
   ```

3. Record the existing subvolumes (must show `home`, `nix`, and possibly
   `steamlib`):

   ```bash
   sudo btrfs subvolume list -o /mnt/btrfs
   ```

## 3. Create `@` and copy the root tree into it

```bash
sudo btrfs subvolume create /mnt/btrfs/@
cd /mnt/btrfs

sudo bash -c '
  set -euo pipefail
  shopt -s dotglob nullglob
  for e in *; do
    [ "$e" = "@" ] && continue
    if btrfs subvolume show "$e" >/dev/null 2>&1; then
      echo "skip subvolume: $e"
      continue
    fi
    echo "copying: $e"
    cp -a --reflink=auto -- "$e" "@/"
  done
'
```

Notes:

- Never copy a subvolume (`home`, `nix`, `steamlib`): `cp` would duplicate its
  contents, and `/nix` is tens of GB. The `btrfs subvolume show` check is what
  skips them — keep it.
- `--reflink=auto` keeps the copy cheap on btrfs (no data duplication).
- If free space is insufficient, replace `cp … "@/"` with `mv -- "$e" "@/"`.
  `mv` across subvolumes is a copy+unlink: single space requirement, but no
  fallback if something goes wrong.

Verify:

```bash
sudo ls /mnt/btrfs            # only: @  home  nix  (and steamlib)
sudo ls /mnt/btrfs/@          # etc  var  usr  root  srv  opt  tmp  boot? no (/boot is vfat)
sudo du -sh /mnt/btrfs/@      # roughly the du value from step 0
```

Unmount and reboot:

```bash
sudo umount /mnt/btrfs
sudo cryptsetup close xpsroot
# reboot, no USB
```

systemd-boot boots the default (new) generation, which mounts `subvol=@`. If the
boot menu is shown, pick the generation built in step 1 — **not** an older one
(older generations still mount the top level, which now has no root files).

## 4. Verify the boot

```bash
findmnt -no OPTIONS /
# expect: rw,relatime,compress=zstd:3,ssd,space_cache=v2,subvolid=256,subvol=/@
btrfs subvolume show / | head
btrfs subvolume list /
systemctl --failed
sudo nixos-rebuild switch --flake /etc/nixos
```

Expected after the switch: `/` = `@`, `/home` = `home`, `/nix` = `nix`,
no failed units, `nix flake check`-less rebuild completes.

## 5. Delete the old tree from the top level

Once the system boots cleanly, the old copies are still in the top level. Mount
it from the running system (allowed: the top level is no longer mounted at `/`)
and remove only the non-subvolume entries:

```bash
sudo mkdir -p /mnt/top
sudo mount -o subvolid=5 /dev/mapper/luks-45c077f9-a627-4815-9a19-a1d6e33cb7c7 /mnt/top

sudo bash -c '
  set -euo pipefail
  cd /mnt/top
  shopt -s dotglob nullglob
  for e in *; do
    [ "$e" = "@" ] && continue
    btrfs subvolume show "$e" >/dev/null 2>&1 && continue   # never delete subvolumes
    echo "removing leftover: $e"
    rm -rf -- "$e"
  done
'

# optional, once every account has reinstalled its games:
sudo btrfs subvolume delete /mnt/top/steamlib

sudo umount /mnt/top
```

## 6. Snapshots (now possible)

With `@` in place, root snapshots work. Example layout (create the directory as
a subvolume so it is not itself part of the root snapshot):

```bash
sudo btrfs subvolume create /snapshots
sudo btrfs subvolume snapshot / /snapshots/root-$(date +%F-%H%M)
sudo btrfs subvolume list / | grep snapshots
```

Snapshots of `/` contain `/etc`, `/var`, `/usr`… but **not** `/home` or `/nix`
(separate subvolumes).

## 7. If something goes wrong

- **New generation fails to boot**: boot the live ISO, mount the top level as in
  step 2, check `/mnt/btrfs/@` (it should contain the full tree) and
  `/mnt/btrfs/home`, `/mnt/btrfs/nix`. Mount `@` over `/mnt`, bind-mount
  `/nix`, `/dev`, `/proc`, `/sys`, `/run`, enter with `nixos-enter`, fix
  `hosts/laptop-xps/hardware-configuration.nix`, and run
  `nixos-rebuild boot --flake /etc/nixos`.
- **Nothing boots / `@` is damaged**: the original tree is still intact until
  step 5 — revert the config line to `options = [ "compress=zstd" "noatime" ];`,
  boot the old generation, and start over.
- **Out of space during the copy**: stop, unmount, and retry with the `mv`
  variant (step 3), or first delete regenerable data (`/var/cache`, old
  generations via `sudo nix-collect-garbage -d`).

## 8. Checklist

- [ ] Backups done; free space ≥ root-only usage.
- [ ] `subvol=@` set in `hardware-configuration.nix`; `nixos-rebuild boot` done.
- [ ] ISO booted; LUKS opened; top level mounted; subvolumes recorded.
- [ ] `@` created; only non-subvolume entries copied.
- [ ] Reboot into the **new** generation; `findmnt /` shows `subvol=/@`.
- [ ] `systemctl --failed` clean; `nixos-rebuild switch` successful.
- [ ] Leftovers removed from the top level; optional `steamlib` deleted.
- [ ] Optional `/snapshots` subvolume created.
