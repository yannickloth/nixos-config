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

> **NOTE — not applied.** `big-parallel` is part of the nixpkgs `nix.settings.system-features` default (`[ "nixos-test" "benchmark" "big-parallel" "kvm" ]`). Nix concatenates list values, so re-listing a subset duplicates features and cannot remove `big-parallel`. Dropping it would require `lib.mkForce` on the whole list — not worth overriding the NixOS default. Left to the default.

### P2.3 Centralize per-host `max-jobs`/`cores`
hera & p16 set `max-jobs = 12` + `cores = 0` identically; xps=4. Centralize (e.g. in `roles/psd.nix` or a nix-tier module) as a single per-host declaration.

### P2.4 btrfs `compress=zstd` + `noatime` on hera/p16
xps already got these (this session). hera/p16 `/` mounts only have `subvol=@`; apply the same SSD-hygiene options.

---

## P3 — Security & maintainability

### P3.1 nftables firewall
`laptop-firewall.nix:7` has `#nftables.enable = true;` commented. Move to nftables for the small open port set.

> **DONE** — nftables enabled. The two iptables `extraCommands` blockers were both in this repo's own modules (not nixpkgs): SONOS (`services/sonos.nix`) and Samba (`services/samba.nix`). Converted:
> - **SONOS**: replaced the `ipset create upnp` iptables hack with a native nftables table (`networking.nftables.tables.sonos-ssdp`) using a `set` with a 3s timeout that tracks outbound SSDP M-SEARCH (ip . sport) and accepts the short-lived unicast replies. No ipset needed.
> - **Samba**: removed the `netbios-ns` iptables CT-helper `extraCommands` line (unnecessary; `openFirewall` already opens UDP 137/138).
> `networking.firewall.extraCommands` is now empty; `networking.nftables.enable = true`; `nix flake check` passes on all hosts.

### P3.2 Tor transparent proxy off by default
`services/tor.nix` forces `transparentProxy.enable = true` on all traffic. Prefer SOCKS-on-demand (keep `TOR_SOCKS_PORT`).

### P3.3 Add flake CI / `nix flake check`
No `.github` workflow. A `nixos-rebuild build --flake .#<host>` or `nix flake check` in CI would catch eval/merge regressions.

### P3.4 Resolve nixos-hardware TODO modules
`flake.nix:35,60` have `# TODO check which module may be imported` for hera/p16 (xps has `dell-xps-13-9360`).

> **DONE (documented)** — exact models are not recorded in the repo and cannot be verified from config alone. Updated `flake.nix` comments: p16 keeps the safe generic `lenovo-thinkpad` module; hera's module remains commented with instructions to confirm the model via `sudo dmidecode -s system-product-name` before enabling a specific `dell-xps-13-*` module.

### P3.5 Remove dead imports
`hardware/corsair.nix` (openrazer disabled) and commented `#desktop/gnome.nix`, `#apps/go-scripting.nix` across hosts.

> **Not done (reverted)** — `hardware/corsair.nix` kept. Although it currently sets `ckb-next.enable = false`, it is a deliberate opt-in hook: flipping it to `true` installs/compiles ckb-next for a Corsair keyboard. Not dead weight. Commented-out gnome/go-scripting lines and `openrazer.enable = false` also kept as documentation/intent.

### P3.6 Reproducibility of cachyos-kernel input
`flake.nix:16` tracks a moving `release` branch. Consider pinning or documenting the "latest" choice.

> **DONE** — documented the deliberate "latest" choice in `flake.nix` with instructions for pinning if reproducibility is desired.

---

## Status
**P1: DONE** — earlyoom→oomd, nix-serve bound to loopback (verified on all 3 hosts).

**P2: DONE.** All P2 work complete (with P2.1 done via alternative approach and P2.2 deliberately infeasible — see notes):
- P2.3 **done**: per-host `max-jobs`/`cores` centralized via new `roles.nix.maxJobs`/`roles.nix.cores` options (xps 4/null, hera 12/0, p16 12/0); copy-pasted host blocks removed.
- P2.4 **done**: `compress=zstd` + `noatime` on hera (`/`, `/data`) and p16 (`/`).
- P2.1 **done via alternative approach**: `system-features` NOT hoisted into `roles/nix.nix` — left to the nixpkgs default instead (dedup achieved by removal, not by moving into shared role).
- P2.2 **deferred (infeasible)**: cannot drop `big-parallel` from the nixpkgs default via list concat; would need `mkForce`. See P2.2 note.

**P3: DONE** (P3.4 documented, P3.5 reverted) — `nix flake check` passes:
- P3.1 **done**: nftables enabled; SONOS converted to a native nftables table, Samba netbios-ns iptables helper removed.
- P3.2 tor transparent proxy off (SOCKS on demand), verified false.
- P3.3 CI workflow added (`.github/workflows/ci.yml`: `nix flake check` + eval all 3 hosts).
- P3.4 nixos-hardware TODOs documented (needs physical model verification).
- P3.5 corsair kept (opt-in hook, not dead) — see note.
- P3.6 cachyos-kernel input documented.
- flake.lock updated via `nix flake update` (newer nixpkgs/home-manager/cachyos).

Suggested order: none — plan complete. Follow-ups: confirm hera/p16 models via dmidecode.
