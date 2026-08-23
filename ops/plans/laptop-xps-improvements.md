# Laptop-XPS (Dell 9360, 16 GB) — Improvement Plan

Host: `hosts/laptop-xps/`
Date: 2026-08-22
RAM: 16 GB (soldered, non-upgradeable). CPU: Kaby Lake i7. This is the binding constraint.

Priority: **P1** (high value, low risk) → **P2** (medium) → **P3** (cleanup).

---

## P1 — Memory & Stability (directly addresses the 16 GB limit)

### P1.1 Enable systemd-oomd
Prevents hard lockups when memory is exhausted during heavy workloads (Steam, Waydroid, VMs — all enabled on this host).

> **DONE** — added to `hosts/laptop-xps/laptop-xps.nix`.

```nix
systemd.oomd.enable = true;
systemd.oomd.enableRootSlice = true;
systemd.oomd.enableUserSlices = true;
```

### P1.2 Right-size zram
`environments/laptop.nix` sets `zramSwap.memoryPercent = 50` → 8 GB zram **plus** a 16 GB swapfile. 8 GB zram is oversized; ~25% is the sweet spot for a 16 GB laptop (frees RAM for page cache).

> **DONE** — root cause fixed once and for all: `environments/laptop.nix` now uses `lib.mkDefault 50` for the shared zram default, so hosts override cleanly with a plain value. XPS sets `memoryPercent = 25`; hera/p16 keep 50. No `mkForce` needed.

```nix
# shared environments/laptop.nix
zramSwap.memoryPercent = mkDefault 50;
# host override
zramSwap.memoryPercent = 25;
```

### P1.3 Add `compress=zstd` across btrfs subvols
`hardware-configuration.nix` mounts three btrfs subvols (`/`, `/home`, `/nix`); **none** had `compress=zstd` (the original plan incorrectly claimed `/home` and `/nix` already had it — they only had `subvol=` options). Compression saves disk + improves SSD endurance on a 16 GB machine. `noatime` also applied to all three for SSD hygiene.

> **DONE** — `compress=zstd` + `noatime` added to `/`, `/home`, and `/nix` for whole-disk consistency.

```nix
fileSystems."/" = {
  device = "/dev/mapper/luks-45c077f9-a627-4815-9a19-a1d6e33cb7c7";
  fsType = "btrfs";
  options = [ "compress=zstd" "noatime" ];
};
fileSystems."/home" = {
  device = "/dev/mapper/luks-45c077f9-a627-4815-9a19-a1d6e33cb7c7";
  fsType = "btrfs";
  options = [ "subvol=home" "compress=zstd" "noatime" ];
};
fileSystems."/nix" = {
  device = "/dev/mapper/luks-45c077f9-a627-4815-9a19-a1d6e33cb7c7";
  fsType = "btrfs";
  options = [ "subvol=nix" "compress=zstd" "noatime" ];
};
```

### P1.4 Add fstrim + noatime
SSD hygiene; absent today.

> **DONE** — `services.fstrim.enable = true` in `laptop-xps.nix`; `noatime` in the mount options of P1.3 (all three subvols).

```nix
services.fstrim.enable = true;
# add "noatime" to the mount options in P1.3
```

### P1.5 Cap parallel Nix builds
Commented-out block in `laptop-xps.nix`. Prevents OOM during `nixos-rebuild`.

> **DONE** — `nix.settings.max-jobs = 4` in `laptop-xps.nix`.

```nix
nix.settings.max-jobs = 4;
```

---

## P2 — Security & Network Hygiene

### P2.1 Bind nix-serve to localhost
`services/nix-serve.nix` sets `openFirewall = true` → binary cache exposed on a battery laptop. Restrict.

> **DONE** — shared `services/nix-serve.nix:7-8` sets `openFirewall = false` + `bindAddress = "127.0.0.1"` (applies to all hosts, verified in cross-host plan).

```nix
# in services/nix-serve.nix
openFirewall = false;
bindAddress = "127.0.0.1";
```

### P2.2 Rework the system-wide Tor transparent proxy
`services/tor.nix` forces `transparentProxy.enable = true` on all traffic — heavy on a 16 GB host. Prefer SOCKS-on-demand (keep `TOR_SOCKS_PORT`).

> **DONE** — `services/tor.nix:11` sets `transparentProxy.enable = false`; `TOR_SOCKS_PORT = "9050"` kept (shared, all hosts).

```nix
transparentProxy.enable = false;
```

### P2.3 nftables firewall
`laptop-firewall.nix:7` is commented out. Switch from iptables to nftables for the (small) open port set.

> **DONE** — `environments/laptop-firewall.nix:11` sets `networking.nftables.enable = true`. The two iptables `extraCommands` blockers (SONOS ipset hack, Samba netbios-ns helper) were converted/removed. See cross-host plan P3.1.

```nix
networking.nftables.enable = true;
```

---

## P3 — Cleanup & De-duplication

### P3.1 Trim the workload
This host enables a very large set; several daemons are likely unused on a 16 GB laptop. Candidates to **move to a server host** or disable:
- `clamav` (always-on scanning is costly)
- `samba`, `sonos`, `onedrive`, `syncthing` (network daemons; keep if actually used)
- `nix-serve` (if bound to localhost, it's only useful for local rebuilds — consider disabling entirely)

### P3.2 Drop unused RGB/gaming hardware imports
`hardware/corsair.nix` and `openrazer` are effectively disabled; harmless but slim the build if unused.

> **Deferred** — `hardware/corsair.nix` kept as a deliberate opt-in hook (cross-host P3.5 note). `openrazer` still enabled in `games/games.nix`. Revisit if the build needs slimming.

### P3.3 Document the `psmouse` blacklist
`hardware-configuration.nix:15` blacklists `psmouse` with no comment. Likely a touchpad workaround — add a comment so it isn't removed accidentally.

> **NOT DONE** — xps `hosts/laptop-xps/hardware-configuration.nix:15` still has no comment (hera/p16 both have `# the touchpad does not use psmouse`). Add the same comment.

```nix
blacklistedKernelModules = [ "psmouse" ] ++ lib.optionals (!config.hardware.enableRedistributableFirmware) [ "ath3k" ];
# add: "psmouse" # the touchpad does not use psmouse
```

### P3.4 Resolve VA-API driver ambiguity
Both `intel-vaapi-driver` (via `hardware-configuration.nix`) and `intel-media-driver` (iHD, via `intel_graphics.nix`) are installed. Verify with `vainfo` and keep only the working driver for Kaby Lake (usually iHD).

> **NOT DONE** — `hardware/intel_graphics.nix` still installs both `intel-media-driver` and `intel-vaapi-driver`. Needs `vainfo` on the host to decide.

---

## Out of scope / deferred
- **Dedicated swap partition + hibernation** — `suspend-then-hibernate` needs a real swap partition (LUKS). High value but touches partition layout; separate plan. (Ref: commented block `hardware-configuration.nix:63-73`.)
- **TLP vs power-profiles-daemon** — already decided (PowerDevil + PPD path). Leave as-is.

---

## Status
**P1 (all 5 items): DONE** — implemented and verified via `nix eval` (zram xps=25/hera=50/p16=50; btrfs options uniform; oomd/fstrim/max-jobs correct). Awaiting `sudo nixos-rebuild switch --flake ./` to apply.

**P2 (all 3 items): DONE** — via the cross-host plan (shared roles, applies to all hosts):
- P2.1 nix-serve bound to loopback (`services/nix-serve.nix`).
- P2.2 tor transparent proxy off, SOCKS on demand (`services/tor.nix`).
- P2.3 nftables enabled (`environments/laptop-firewall.nix`).

**P3: partial.**
- P3.1 workload trim — **not started** (needs a decision: which daemons are actually used).
- P3.2 corsair/openrazer — **deferred** (corsair kept as opt-in hook; openrazer still enabled).
- P3.3 psmouse comment — **NOT DONE** (xps `hardware-configuration.nix:15` lacks the comment the other hosts have).
- P3.4 VA-API — **NOT DONE** (needs `vainfo` on the host to pick one driver).

Remaining work: P3.1 (decision), P3.3 (one-line comment), P3.4 (verify + pick driver).
