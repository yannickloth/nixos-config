# IVP Change-Driver Analysis & Modularization Plan

This document records an Independent Variation Principle (IVP) analysis of the
NixOS configuration. It identifies the change drivers governing each element,
assigns drivers to elements, and proposes a modularization that keeps elements
with coinciding driver sets together and separates elements with differing
driver sets.

> **Scope note:** IVP is empirically grounded for software. NixOS config modules
> are treated as the "elements"; the analysis applies IVP analogically.

---

## 1. Change Drivers

A change driver is an external condition that, when it changes, creates a
requirement for an element to be modified. Drivers are identified bottom-up
from the actual repository contents.

| ID | Driver | When it changes | Anchored in |
|----|--------|-----------------|-------------|
| `D-HOST` | Host identity / machine-specific topology | a machine is added/removed/changed (its name, bootloader, hardware scan) | `hosts/<host>/` directories |
| `D-HARDWARE` | Physical hardware / peripherals present | a device is added/removed (CPU, GPU, printer, smartcard reader, controller) | `hardware/` module set |
| `D-SYSTEM` | Base system-wide policy (stateVersion, unfree, session vars, base packages, shared services) | NixOS release policy changes, base tooling changes | nixpkgs option surface |
| `D-DESKTOP` | Desktop environment / display / audio stack choice | the DE/WM/audio stack is swapped or updated | DE project release policy |
| `D-SERVICE` | Network/daemon services offered | a service is added/removed/updated (avahi, samba, tor, …) | upstream service project |
| `D-APP` | User application / language-toolchain tooling | a user-facing app or language toolchain is added/updated | upstream application project |
| `D-GAME` | Gaming software / game inputs | a game or gaming driver is added/updated | upstream gaming project |
| `D-SECURITY` | Security hardening posture | a security standard/threat model changes (sudo, TPM, yubikey) | security policy / standards |
| `D-USER` | User accounts & per-user home-manager state | a user is added/removed, or their dotfiles/preferences change | individual user's needs |
| `D-LLM` | Local LLM / AI inference services | model server or web UI tooling changes | upstream LLM tooling project |
| `D-PKG` | Locally-packaged derivations | the packaged upstream software changes (ffmpeg, xpad, softmaker) | upstream source repo |
| `D-NIX` | Nix tooling / package manager config | nix versions, substituters, GC policy change | nixpkgs / nix itself |
| `D-ENV` | Laptop/mobile vs desktop environment | power/network profile of the class of machine changes | hardware class (laptop) |

---

## 2. Driver Assignment per Element

Each element's driver list is its **change-driver set**. Elements whose sets
coincide belong together; elements whose sets differ belong across a boundary.

### 2.1 Top-level dirs & their driver sets

| Directory | Driver set |
|-----------|-----------|
| `hosts/` | { `D-HOST` } |
| `hardware/` | { `D-HARDWARE` } |
| `roles/` | { `D-SYSTEM`, `D-NIX` } |
| `apps/` | { `D-APP` } |
| `services/` | { `D-SERVICE` } |
| `desktop/` | { `D-DESKTOP` } |
| `games/` | { `D-GAME` } |
| `security/` | { `D-SECURITY` } |
| `users/` | { `D-USER` } |
| `modules/` | mixed (see 2.2) |
| `packages/` | { `D-PKG` } |

### 2.2 The `modules/` directory — driver-set anomaly

`modules/` currently contains three orphaned elements:

| Element | Driver set | Status |
|---------|-----------|--------|
| `modules/llama-server.nix` | { `D-LLM`, `D-SERVICE` } | **not imported anywhere** |
| `modules/timer.nix` | { `D-SYSTEM` } (generic task scheduler) | **not imported anywhere** |
| `modules/xpad.nix` | { `D-HARDWARE`, `D-PKG` } | **not imported anywhere** |

These are dead code. `llama-server` is an LLM service → driver set `{D-LLM,
D-SERVICE}`. `timer` is a generic NixOS task-scheduling facility → `{D-SYSTEM}`.
`xpad` is a hardware kernel module → `{D-HARDWARE, D-PKG}`.

Because their driver sets **differ** from each other AND from the parent
`modules/` label (which has no coherent single driver), `modules/` is a
misnomer: it groups by "it's a module" (a proxy reasoning violation) rather
than by change driver.

### 2.3 The `users/nicky/` directory — driver-set overlap

| Element | Driver set |
|---------|-----------|
| `users/nicky/nicky.nix` | { `D-USER` } (account + groups) |
| `users/nicky/nicky-hm.nix` | { `D-USER` } (home-manager, wired into NixOS) |
| `users/nicky/home.nix` | { `D-USER` } (standalone home-manager flake config) |
| `users/nicky/flake.nix`, `flake.lock` | { `D-USER` } (standalone home-manager flake) |
| `users/nicky/secrets.nix`, `secrets.example.nix` | { `D-USER` } (per-user secrets) |
| `users/nicky/emacs-config.el` | { `D-USER` } (dotfile) |
| `users/nicky/localai.nix`, `openwebui.nix` | { `D-LLM`, `D-USER` } |

These all share `D-USER`, so co-locating them is correct. **But** there is a
**duplication problem**: `nicky-hm.nix` (NixOS-wired home-manager config) vs
`home.nix` (standalone home-manager flake config) both configure nicky's home
environment — two elements with the same driver set `{D-USER}` that are kept
separate. Per IVP, coinciding driver sets → same side of boundary. This is a
violation: a change to nicky's dotfiles must be made twice.

`localai.nix` / `openwebui.nix` have driver set `{D-LLM, D-USER}` — they differ
from the other nicky files by `D-LLM`, but they're orphaned (not imported).

---

## 3. Cross-checking current vs proposed groupings

### 3.1 Findings (things already correct)

- `apps/`, `services/`, `desktop/`, `games/`, `security/`, `hardware/`
  separate cleanly — each has a single dominant driver. ✓
- `roles/` correctly gathers `{D-SYSTEM, D-NIX}` base policy. ✓
- `hosts/` correctly isolates `D-HOST`. ✓

### 3.2 Problems found

| # | Problem | Type |
|---|---------|------|
| P1 | `modules/` is a proxy-reasoning grouping; its 3 members have mutually differing driver sets | IVP violation |
| P2 | `modules/llama-server.nix`, `timer.nix`, `xpad.nix` are dead (never imported) | dead code |
| P3 | `users/nicky/localai.nix`, `openwebui.nix` are orphaned (moved but never imported) | dead code |
| P4 | `nicky-hm.nix` and `home.nix` duplicate the same `{D-USER}` config | IVP violation (same driver set kept apart) |
| P5 | `packages/development/ffmpeg` is a nested flake (own flake.lock) inside the repo flake — a second driver source for `D-PKG` | boundary ambiguity |
| P6 | `users/nicky/flake.nix` + `home.nix` (standalone home-manager flake) coexists with the NixOS home-manager wiring — two entry points for the same user | duplication |

---

## 4. Proposed Modularization

### 4.1 Resolve `modules/` (fixes P1, P2)

Dissolve `modules/`:

- `llama-server.nix` → `services/llama-server.nix` (driver `{D-LLM, D-SERVICE}`). Import it (or delete it — see 4.4).
- `timer.nix` → `roles/tasks.nix` (driver `{D-SYSTEM}`).
- `xpad.nix` → `hardware/xpad.nix` (driver `{D-HARDWARE, D-PKG}`).
- Delete `modules/` entirely.

### 4.2 Unify nicky's home-manager config (fixes P4, P6)

Pick ONE home-manager entry point for nicky. Recommended: keep `nicky-hm.nix`
(NixOS-wired), delete the standalone `home.nix` + `flake.nix` + `flake.lock`
(or move them out of the repo tree to a separate repo). The standalone flake
duplicates `D-USER` work and cannot be cleanly nested inside the main flake.

### 4.3 Wire or delete the LLM orphans (fixes P3)

`localai.nix` / `openwebui.nix` — either import them into `nicky-hm.nix` (they
become live `{D-LLM, D-USER}` elements) or delete them. As-is they are dead.

### 4.4 `roles/system.nix` — check for driver cohesion

`roles/system.nix` currently mixes:
- `D-SYSTEM` base policy (unfree, session vars, base packages, programs) ✓
- `D-SERVICE` (openssh, syncthing, tailscale, ananicy services) — **mixed**

Per IVP, `{D-SYSTEM}` and `{D-SERVICE}` differ. Consider splitting the
`services` block out of `roles/system.nix` into `roles/system-services.nix` or
into `services/`. **However** these are common-across-hosts services, which is
why they landed in `roles/`. Document this as a readability-vs-driver trade-off
(see 4.6).

### 4.5 `packages/` nested flake (fixes P5)

`packages/development/ffmpeg` being its own flake with a flake.lock means two
flake sources govern `D-PKG`. Convert the ffmpeg derivation to a plain
derivation consumed by `roles/system.nix` (or delete it, since it's commented
out everywhere).

### 4.6 Labeling

| Proposed separation | Grounds |
|--------------------|---------|
| `modules/` → `services/`, `roles/`, `hardware/` | IVP-prescribed (differing driver sets) |
| nicky home-manager unification | IVP-prescribed (coinciding driver sets kept apart) |
| LLM orphans wired/deleted | IVP-prescribed (dead elements) |
| `roles/system.nix` service block split | IVP-prescribed (D-SYSTEM vs D-SERVICE), **unless** keeping them together is justified by "all-hosts service defaults" → then readability/co-location trade-off, documented |

---

## 5. Driver-Set Relationship Matrix (key pairs)

| Element A | Element B | Relationship | Verdict |
|-----------|-----------|--------------|---------|
| `services/avahi.nix` | `services/samba.nix` | differ (`D-SERVICE` but distinct services) | both in `services/` (same `D-SERVICE` at the service-domain granularity) ✓ |
| `apps/java.nix` | `services/tor.nix` | differ (`D-APP` vs `D-SERVICE`) | separate ✓ |
| `modules/llama-server.nix` | `services/tor.nix` | partial overlap (both have `D-SERVICE`) | `llama-server` → `services/` |
| `modules/xpad.nix` | `hardware/bluetooth.nix` | overlap on `D-HARDWARE` | `xpad` → `hardware/` |
| `nicky-hm.nix` | `home.nix` | **coincide** (`{D-USER}`) | **should merge** |
| `roles/system.nix` (services block) | `services/` | share `D-SERVICE` | consider moving block |

---

## 6. Confidence & Gaps

- **High confidence:** P1/P2/P3/P4 — dead code and duplication are verifiable facts.
- **Medium confidence:** P4/P6 recommendation to delete the standalone
  home-manager flake — depends on whether the user uses it independently of the
  NixOS flake (a legitimate separate `D-USER` driver if used standalone).
- **Open question:** whether `roles/system.nix`'s service block should move to
  `services/` depends on whether the "applied to all hosts" property is meant
  to be a distinct driver. Flagged for user decision.
- **Not analyzed in depth:** actual per-host system package differences inside
  `hosts/<host>/*-configuration.nix` (low driver conflict — all `D-HOST`).
