# CachyOS host tuning for Strata (laptop-p16)

laptop-p16 runs **CachyOS + standalone home-manager** (`users/flake.nix`), so
the NixOS system modules do not apply here. Two engine requirements therefore
live in `/etc`:

- **2 MiB hugetlb pool** large enough for Strata's whole expert arena. The
  arena is one ~40 GiB anonymous mmap with `MAP_HUGETLB|MAP_HUGE_2MB`
  (`src/core/pinned.cu`); the mmap is all-or-nothing, so a pool even one page
  short makes the whole arena fall back to 4 KiB pages (8.3M TLB entries). The
  IQ3_XXS arena is 39.97 GiB = 20465 pages; `22528` = 44 GiB.
- **Unlimited `RLIMIT_MEMLOCK`** for nicky's shells and for the systemd user
  manager, because `MAP_HUGETLB` charges the mapping to `MEMLOCK`. The strata
  user unit already sets `LimitMEMLOCK=infinity` (`packages/strata/home.nix`),
  but that is capped by the user manager's inherited 8 MiB without the drop-in.

Install (needs root):

```sh
sudo ./install.sh
```

Then **reboot** (or re-login). The hugepage pool is reserved by systemd-sysctl
early at boot, before Strata starts, so it never competes with the live pinned
arena. Verify:

```sh
grep HugePages_Total /proc/meminfo          # 22528
ulimit -l                                   # unlimited
```

The NixOS host config in `hosts/laptop-p16/` (`hardware-configuration.nix`,
`laptop-p16.nix`) keeps the equivalent settings for the day this laptop is
reinstalled with NixOS; nothing in the shared home-manager modules depends on
which of the two is in use.

## nix-serve cache (nicky user service)

The peer Nix cache the other laptops substitute from (`roles/nix.nix` lists
`http://laptop-p16.bee-blues.ts.net:5000/`) is a **nicky user service**
managed by the standalone home-manager deployment (`users/nix-serve.nix`);
the NixOS `services/nix-serve.nix` system unit does not apply on CachyOS. It
starts at login and keeps running after logout because the orca-server
activation (`packages/orca/home.nix`) enables lingering for nicky.

The signing key needs no manual setup: `secrets/nix-cache-laptop-p16.key.age`
is encrypted to the `host-laptop-p16` key (for a future NixOS reinstall)
**and** `user-nicky`, so home-manager's agenix module decrypts it on every
switch with nicky's user identity `~/.ssh/agenix_nicky` (distributed by
`services/ssh-user-keys.nix`; the same mechanism the opencode provider keys
use on this host). Without the key the cache would serve unsigned narinfos
that peers (`require-sigs`, the default) ignore.

Apply and verify:

```sh
home-manager switch --flake ~/code/nixos-config/users#nicky
systemctl --user status nix-serve
curl -s http://127.0.0.1:5000/nix-cache-info
# from a peer laptop (xps/hera):
curl -s http://laptop-p16.bee-blues.ts.net:5000/nix-cache-info
```

## /data automount (`automount-data.sh`)

`/data` is a second LUKS volume (`nvme0n1p1`, btrfs, fs UUID
`fbaa1e9e-…`). Its `/etc/fstab` line carries `nofail` but nothing opened the
LUKS container at boot, so the mapper never appeared and the volume came back
only after a manual `cryptsetup open` + `mount` with the passphrase.

That is tolerable for a Steam library and fatal for podman: Unsloth Studio's
container keeps its graphroot at `/data/containers/nicky`
(`packages/unsloth-studio/container.nix`, option `podmanStorageRoot`), and
`storage.conf` is user-wide — with `/data` missing, every `podman` command
fails, not just the Studio unit.

`automount-data.sh` fixes it, idempotently and with root:

```sh
sudo ./automount-data.sh
```

It creates `/etc/luks/data.key` (0400, root), enrols it as an additional LUKS
key (the passphrase slot stays as the recovery path), adds an
`/etc/crypttab` line so `systemd-cryptsetup` unlocks at boot, and adds
`x-systemd.automount` to the fstab line so a late unlock still resolves on
first access. It does **not** replace the passphrase: keep it.

Verify after the next boot:

```sh
systemctl status data.automount data.mount
df -h /data
```

### The same volume on NixOS

`/etc/crypttab` and `/etc/fstab` on NixOS are generated, so the script must not
edit them there. `hosts/laptop-p16/data-volume.nix` declares both instead, and
the script drops to `--key-only` by itself when it finds `/etc/NIXOS`: it then
does only the part NixOS cannot do declaratively — generate the keyfile and add
it to a LUKS keyslot:

```sh
sudo ./automount-data.sh --key-only
```

The keyfile path is the same on both installs (`/etc/luks/data.key`), so the
file migrated from the CachyOS install keeps working; a fresh NixOS install
re-enrols the key once with the existing passphrase. The key is deliberately
not a Nix store path: `environment.etc` would copy it into `/nix/store`
world-readable.

