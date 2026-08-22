# Cross-Host Improvements — Plan

Applies to all three laptops (`laptop-hera`, `laptop-p16`, `laptop-xps`) via shared roles, or as a consistent per-host pattern.
Date: 2026-08-23

Priority: **P1** (low risk, removes real conflicts/exposure) → **P2** (consistency/dedup) → **P3** (maintainability/hygiene).

---

## P1 — Unify OOM handling & harden nix-serve

### P1.1 earlyoom → systemd-oomd everywhere
`roles/base.nix` enables `services.earlyoom` on all systems; `systemd-oomd` was added only on xps. Running both on xps is redundant/conflicting. Unify on `systemd-oomd`.

```nix
# roles/base.nix: replace earlyoom with oomd
systemd.oomd = {
  enable = true;
  enableRootSlice = true;
  enableUserSlices = true;
};
# remove: services.earlyoom.enable = mkDefault true;
```

Then drop the xps-local oomd block (`laptop-xps.nix`), now redundant.

### P1.2 Bind nix-serve to localhost
`services/nix-serve.nix:6` sets `openFirewall = true` → binary cache exposed on `0.0.0.0` on all hosts. Restrict.

```nix
# services/nix-serve.nix
openFirewall = false;
bindAddress = "127.0.0.1";
```

---

## P2 — Consistency / dedup (shared roles)

### P2.1 Hoist duplicated `system-features` + `nix.settings`
The identical `system-features` list is copy-pasted in all three host files. Move to `roles/nix.nix`; keep only per-host `max-jobs`.

### P2.2 Drop self-contradictory `big-parallel`
Inline comment warns it's for >16 cores, but all hosts are ≤8-core. Remove from the shared list.

### P2.3 Centralize per-host `max-jobs`/`cores`
hera & p16 set `max-jobs = 12` + `cores = 0` identically; xps=4. Centralize (e.g. in `roles/psd.nix` or a nix-tier module) as a single per-host declaration.

### P2.4 btrfs `compress=zstd` + `noatime` on hera/p16
xps already got these (this session). hera/p16 `/` mounts only have `subvol=@`; apply the same SSD-hygiene options.

---

## P3 — Security & maintainability

### P3.1 nftables firewall
`laptop-firewall.nix:7` has `#nftables.enable = true;` commented. Move to nftables for the small open port set.

### P3.2 Tor transparent proxy off by default
`services/tor.nix` forces `transparentProxy.enable = true` on all traffic. Prefer SOCKS-on-demand (keep `TOR_SOCKS_PORT`).

### P3.3 Add flake CI / `nix flake check`
No `.github` workflow. A `nixos-rebuild build --flake .#<host>` or `nix flake check` in CI would catch eval/merge regressions.

### P3.4 Resolve nixos-hardware TODO modules
`flake.nix:35,60` have `# TODO check which module may be imported` for hera/p16 (xps has `dell-xps-13-9360`).

### P3.5 Remove dead imports
`hardware/corsair.nix` (openrazer disabled) and commented `#desktop/gnome.nix`, `#apps/go-scripting.nix` across hosts.

### P3.6 Reproducibility of cachyos-kernel input
`flake.nix:16` tracks a moving `release` branch. Consider pinning or documenting the "latest" choice.

---

## Status
**P1: DONE** — both items implemented and verified via `nix eval` across all three hosts (earlyoom=false, oomd=true, nix-serve openFirewall=false + bind 127.0.0.1).
**P2 / P3: not started.**

Suggested order: P2 → P3.
