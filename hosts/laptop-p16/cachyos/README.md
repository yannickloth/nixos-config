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
