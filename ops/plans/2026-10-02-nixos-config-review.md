# nixos-config review, IVP refactor, and improvement plan

- **Date:** 2026-10-02
- **Status:** proposed (no changes applied yet)
- **Scope:** every `*.nix` in the repo (~120 files, ~8,940 lines), plus
  `flake.nix`/`users/flake.nix`, CI, `scripts/`, `secrets.nix`, and the docs.
- **Method:** manual read of the whole tree + a fresh IVP (Independent
  Variation Principle) pass. This supersedes the (now removed) stale
  `docs/ivp-analysis.md`, which described a `modules/` tree that no longer
  exists.

---

## 1. Decisions locked

- `users.mutableUsers = false` globally. Remove the `true` override in
  `users/users.nix`. This matches `AGENTS.md` and `roles/base.nix`.
- Passwords leave git. One agenix secret per user, referenced via
  `users.users.<n>.hashedPasswordFile` (accepts a crypt hash; `passwordFile`
  expects plaintext). Rotation = edit the secret + rebuild; users cannot
  self-change (acceptable for this threat model).
- Password secrets are encrypted to **host keys only**, not the union, so one
  user key cannot read another user's hash.
- No AD / LLDAP for now (see §6).
- Break-glass: keep the existing wheel + passwordless-sudo root path, and add
  `users.users.root.hashedPasswordFile` as a safeguard.

---

## 2. Findings — correctness / latent bugs (highest priority)

| # | Where | Problem | Proposed fix |
|---|-------|---------|--------------|
| B1 | `roles/base.nix:23` vs `users/users.nix:5` | `mutableUsers` effectively `true` (plain value beats `mkDefault false`), contradicting the stated invariant and `AGENTS.md`. | Delete the override; adopt `false` + agenix (decision §1). |
| B2 | `users/sven/sven.nix` | No `hashedPassword`/`initialPassword`. On a fresh install sven's account is locked and cannot log in. | Add a sven password secret + `hashedPasswordFile`. |
| B3 | `users/{nicky,aeiuno,aaron}/*.nix` | Password hashes committed to git; nicky/aeiuno are bcrypt **cost 05** (weak), aaron is sha512-crypt with a stale `TODO` above it. | Move all four to `hashedPasswordFile` agenix secrets; unify scheme. |
| B4 | `services/tor.nix:30-31` | Uses `iptables` while the firewall is nftables-only (`environments/laptop-firewall.nix:11`); rules live outside the declarative firewall and are not reverted on removal; only blocks `127.0.0.1`. | Convert to nftables (`extraInputRules`), or drop and document. |
| B5 | `services/network-manager.nix:18` | Comment says "disable wpasupplicant" but code is `wireless.enable = lib.mkForce true`; also `appendNameservers` dilutes the XPS family-DNS ordering; `dnsmasq.enable = false` with settings is dead. | Fix comment/code, use `insertNameservers`, remove dead dnsmasq block. |
| B6 | `roles/base.nix:19-20` | Comment "use UTC… do not leak location" but sets `Europe/Luxembourg` (forced again in `environments/laptop.nix:51`). | Reconcile comment with value. |
| B7 | `apps/bittorrent.nix:11` | Opens TCP 51413 while Transmission is commented out → firewall hole. | Remove or re-enable. |
| B8 | `services/openssh.nix` | Duplicates `services/system.nix` openssh enable; hardcodes `networking.nat.externalInterface = "wlp58s0"` and reopens port 22. | Fold into `services/system.nix`; drop the hardcoded interface. |
| B9 | `packages/strata/engine.nix:160,205` | Hardcodes `/usr/lib/libcuda.so.1` (CachyOS host path) into a derivation; RUNPATH dangles on NixOS and the package cannot build in CI. | Use `autoAddDriverRunpath`/guard the symlink. |
| B10 | `users/nicky/nicky-hm.nix:590` | `ExecStop = "/usr/bin/fusermount3"` hardcodes a CachyOS path; unit fails on NixOS. | Reference a Nix-provided `fusermount3`. |
| B11 | `users/aeiuno/aeiuno-hm.nix` + `users/opencode.nix:305` | aeiuno has no `nodejs`, but the Jev MCP runs `npx -y`; likely broken for aeiuno. | Add `nodejs` or resolve the executable with `lib.getExe`. |
| B12 | `games/games.nix:49` vs `users/{sven,aaron}/*-hm.nix` | `gcompris` installed both system-wide and per-kid → duplicate. Same file installs adult games for the kids; `services/malcontent.nix:20-24` claims AppArmor defines no kid profiles, but `security/apparmor.nix:11-53` does. | Remove the duplicate; reconcile the malcontent comment. |
| B13 | `docs/ivp-analysis.md` | Analyzes a `modules/` dir and files (`modules/llama-server.nix`, `users/nicky/home.nix`, `localai.nix`, `packages/development/ffmpeg`, …) that no longer exist. | Replace with this doc's IVP section, or delete. |
| B14 | `.github/workflows/ci.yml` | Cannot pass: private `git+ssh://…forksStrata` input has no runner key; `nix flake check` would also try to build the CUDA `strata` package. | Add a deploy-key secret, and/or eval with a dummy `--override-input` + `--no-build`. |
| B15 | `hosts/laptop-xps/laptop-xps.nix:77-80` | HM modules are `import`ed without `commonHm.hostName` (defaults `""`), unlike hera/p16. Functionally OK today but a latent trap. | Use the same hostName-passing form, or document the default. |

---

## 3. Findings — security / secrets

| # | Where | Problem | Proposed fix |
|---|-------|---------|--------------|
| S1 | `secrets.nix`, `secrets-structure/README.md` | Union recipients: every secret is encrypted to all host **and user** keys, so sven/aaron/aeiuno keys decrypt the Syncthing GUI password, all Open WebUI provider keys, and nicky's API keys. Undercuts the kid isolation enforced everywhere else. | Per-secret scoping: system secrets → host keys; `nicky.nix.age` → user-nicky; Syncthing device keys → owning host; passwords → host keys. |
| S2 | `scripts/agenix-backup.sh` | Writes an unencrypted tar of **all** private keys into the repo dir (gitignored, but plaintext, default umask). | Encrypt the archive (age) or write to a 0700 path + `chmod 600`. |
| S3 | all user files | Password hashes in git (B3). | See §1. |
| S4 | `security/sudo.nix:8` | `wheelNeedsPassword = false` (passwordless sudo). | Acceptable given kids are asserted non-wheel; add a note / keep the assertion. |
| S5 | `infra.md:79-84` | Syncthing is replication, not backup; `restic` is installed but has no scheduled job. | Declarative restic timer to nestor/offsite (agenix secret). |
| S6 | `secrets.nix` vs `secrets-structure/README.md` | Key inventory omits aeiuno/sven/aaron/travelmate recipients that exist in `secrets.nix`. | Reconcile docs with the actual recipient set. |

---

## 4. Findings — hygiene, reproducibility, bloat

- H1: Large commented-out config across the tree (softmaker, transmission, kubernetes, postgresql, libreoffice, gnome, jitsi, go-scripting, virtualbox, `secrets/*.example`). Prefer deletion (git preserves history) or explicit feature flags.
- H2: `displaylink-580.zip` (18 MB) is tracked in git; `laptop-hera-dotconfig-syncthing{,.zip}` (~8 MB) sit untracked in the repo root and contain plaintext cert/key. Move to releases/assets; gitignore.
- H3: Formatter ambiguity — devShell ships `nixpkgs-fmt`, some hosts install `nixfmt`, `.editorconfig` says 2-space. Standardize on `nixfmt-rfc-style` and enforce in CI.
- H4: `apps/typst.nix:11` assigns `config.environment.systemPackages = typstPackages` (overwrite-shaped, list-merged) — style.
- H5: `desktop/hyprland.nix` adds a cachix substituter for an unused WM; `flake.nix`'s `kernels` indirection exists for a single kernel; `specialArgs` is repeated 3×.
- H6: `.idea/` mostly tracked, `.vscode/settings.json` tracked — decide whether IDE dirs belong.
- H7: `users/sven/result`, `users/tmp/`, root `result` are stale symlinks/dirs (gitignored) — cleanup.
- H8: `masterpdfeditor` override duplicated in `roles/system.nix:10` and `users/nicky/nicky-hm.nix:168`, already diverged. Extract to `packages/`.

---

## 5. IVP analysis (fresh, current tree)

### 5.1 Change drivers

| ID | Driver | When it changes |
|----|--------|-----------------|
| D-HOST | Machine identity / bootloader / hardware scan | a machine is added/removed/changed |
| D-HARDWARE | Physical peripherals | a device is added/removed |
| D-SYSTEM | Base system-wide policy (stateVersion, unfree, base packages, session vars) | NixOS release / base tooling |
| D-DESKTOP | DE / WM / audio stack | desktop stack changes |
| D-SERVICE | Network/daemon services | a service changes |
| D-APP | User application / language toolchain | an app/toolchain changes |
| D-GAME | Gaming software / inputs | a game/driver changes |
| D-SECURITY | Security hardening posture | threat model / standards |
| D-USER | User accounts & per-user HM state | a user or their dotfiles change |
| D-LLM | Local LLM / AI inference services | model-server tooling changes |
| D-PKG | Locally-packaged derivations | packaged upstream changes |
| D-NIX | Nix manager config (versions, substituters, GC) | nixpkgs / nix changes |
| D-ENV | Laptop/mobile class profile | the class of machine changes |

### 5.2 Anomalies in the current tree

- **P1 (biggest win) — host import lists are near-duplicates.** Measured:
  hera 62, p16 63, xps 64 imports; **60 shared by all three**. Their driver set
  is `{D-SERVICE,D-APP,D-DESKTOP,D-HARDWARE}`, not `{D-HOST}`. Drift already
  exists (hera: bittorrent; xps: noson+plasma; gnome/jitsi/postgresql/
  virtualbox commented everywhere). **Fix:** a single
  `profiles/family-laptop.nix` importing the common set; hosts keep only the
  real deltas (kernel, printers, psd, RAM, per-host apps).
- **P2 — dead/orphan elements:** `desktop/hyprland.nix` (unused),
  `services/{onedrive,virtualbox,kubernetes,postgresql,cifs-nestor}.nix`,
  `hardware/corsair.nix`, `hardware/printers/canon-selphy-cp1300.nix` (empty),
  `apps/{jitsi-meet,cd-dvd}.nix`, `packages/applications/office/softmaker/*`
  (all invocations commented out). Delete or wire explicitly.
- **P3 — inverted naming/role boundary:** `roles/system.nix` holds base
  packages/programs (D-SYSTEM) while `services/system.nix` holds daemons and is
  imported *by* `roles/system.nix`. Clarify: `roles/base.nix` = policy/
  invariants, `roles/system.nix` = base packages/programs, `services/*` =
  daemons.
- **P4 — home-manager wiring triplicated** in `flake.nix` (identical block 3×)
  and re-implemented in `users/flake.nix`. Extract `mkNixosHost`/`mkHome`.
- **P5 — `masterpdfeditor` duplicated** (H8).
- **P6 — the `extraGroups` conditional block is copy-pasted across all four
  user files.** Same driver set kept apart. Extract a shared module.
- **P7 — doc count drift:** README "34 folders", `pool.nix` header "36 folders
  + 9 devices"; actual **37 folders / 11 devices**.

---

## 6. Considered alternatives

**AD / Synology Directory Server (or Samba AD DC in a VM).** Rejected for now.

- Gains: central identity, self-service password change, policy, unified
  Samba/NAS auth, Kerberos/SSO, Windows-friendly.
- Costs: always-on DC (single point of failure; mobile laptops off-LAN can
  only use cached creds), NixOS SSSD/Kerberos/DNS/time-sync complexity, PAM
  integration with `pam_malcontent`, break-glass admin per host, larger attack
  surface — and it still does not replace agenix for non-password secrets.
- Revisit if: self-service passwords, SSO, centralized sudo/polkit/group
  management, Windows clients, or >~10 users/assets become requirements.
  A lighter middle path would be **LLDAP** (tiny LDAP) + SSSD.

For 4 users / 3 laptops with no IdP, `mutableUsers = false` + agenix is the
right analogue: declarative, no always-on dependency, rotation via rebuild.

---

## 7. Phased execution plan

### Phase 0 — safety net (do first)
- devShell: add `deadnix`, `statix`, `nixfmt-rfc-style`.
- Add `checks.${system}.format` and CI steps: `nix fmt --check`, `deadnix
  --fail`, `statix check`, and a parse pass over all `*.nix`.
- Fix CI's private `forksStrata` input (deploy key secret, or dummy
  `--override-input` + `--no-build`).

### Phase 1 — correctness (small, high value)
- Adopt `mutableUsers = false`; add sven's password; migrate all four hashes to
  agenix `hashedPasswordFile`; verify agenix-mounts-before-`users`-activation
  ordering.
- B4-B12 fixes (tor/nftables, network-manager, timezone comment, bittorrent
  hole, openssh dedupe, `fusermount3`, aeiuno `npx`, gcompris duplicate).

### Phase 2 — IVP structural refactor
- P1 family-laptop profile + host deltas.
- P4 `mkNixosHost`/`mkHome`.
- P6 shared user-group module; P5 extract `masterpdfeditor`.
- P2 delete orphans; P7 fix doc counts; replace stale IVP doc.

### Phase 3 — secrets
- Per-secret recipient scoping + rekey-script support; encrypt the backup
  archive; narrow the union.

### Phase 4 — operational
- Declarative restic backup timer (agenix secret).
- Resolve nixos-hardware model TODOs; optionally `treefmt-nix`,
  `flake-parts`, `nh`/`just` for the common commands.

---

## 8. Risks / verification

- **Password migration is blocked** on the users' plaintext passwords: hashes
  cannot be generated without them. Needs the user to supply them (or run
  `mkpasswd` themselves) before the agenix secrets can be created.
- agenix vs `users` activation ordering for `hashedPasswordFile` must be
  verified for the pinned agenix version.
- Phase 1 network/desktop changes (tor, network-manager) affect connectivity;
  apply behind `nixos-rebuild test` on a machine and confirm before `switch`.
- `nix flake check` scope with the private input and the CUDA `strata` build
  must be settled before CI can be trusted.

---

## 9. Blockers for immediate work

1. ~~Plaintext passwords for nicky, aeiuno, sven, aaron (to generate hashes).~~
   Resolved: hashes provided and sealed (see Progress).
2. Confirm whether to add `nodejs` for aeiuno or resolve `npx` differently.
   Resolved: `nodejs` added in `users/opencode.nix`.
3. ~~Confirm the CI approach (deploy key vs dummy input).~~ Resolved: CI runs
   parse + report-only lint + host eval with the private input overridden by
   public upstream.

---

## 10. Progress log

### 2026-10-02 — Phase 0 + password migration done

- **Phase 0:** `flake.nix` devShell gains `nixfmt`, `deadnix`, `statix`; adds
  `formatter.x86_64-linux = pkgs.nixfmt`. CI rewritten
  (`.github/workflows/ci.yml`): `nix-parse` (blocking), `nix-lint`
  (report-only), `eval-hosts` (public-upstream override, no SSH key needed).
- **Passwords (B1–B3):** `users.mutableUsers = false`; hashes removed from
  `users/*.nix`; new `users/passwords.nix` reads
  `secrets/passwords/<user>.hash.age` via `users.users.<n>.hashedPasswordFile`.
  Secrets encrypted to **host keys only** (verified: host keys decrypt, user
  keys do not).
- **root:** break-glass password secret added (`secrets/passwords/root.hash.age`)
  and `PermitRootLogin = "no"` set in `services/openssh.nix` (root SSH off).
- **B11:** `nodejs` declared in `users/opencode.nix` (fixes aeiuno's `npx` MCP).
- **B (dead file):** deleted empty tracked `hardware/printers/canon-selphy-cp1300.nix`.
- **Verification:** all 128 tracked Nix files parse; `laptop-{hera,p16,xps}`
  toplevels evaluate via the CI override; `password-nicky`/`password-root`
  resolve to `/run/agenix/...`.

### 2026-10-02 — IVP P1 + low-risk correctness fixes

- **IVP P1:** new `environments/family-laptop.nix` holds the 53 modules common
  to all three hosts; each `hosts/<host>/<host>.nix` is now the profile plus its
  real deltas (hera: benchmark; p16: benchmark, obs-studio, wine; xps: noson,
  plasma). Import-set equivalence verified against HEAD — the only semantic
  change is the intentional removal of `services/bittorrent.nix`.
- **B15** done here: all three hosts now set `commonHm.hostName` uniformly
  (laptop-xps previously omitted it).
- **B6** timezone comment; **B7** removed the dead `services/bittorrent.nix`
  firewall hole; **B8** OpenSSH consolidated in `services/openssh.nix` (dropped
  the duplicate enable in `services/system.nix` and the hardcoded `wlp58s0` NAT
  interface + redundant port 22); **B10** nestor-mount uses
  `${pkgs.fuse3}/bin/fusermount3` (added `fuse3` to nicky's packages);
  **B12** removed the duplicate system-wide `gcompris` and corrected the
  malcontent comment.
- **H1/H3:** added `.gitattributes` (`*.age`, `*.tar.gz`, `*.zip` binary).
- **Verification:** 128 files parse; all three toplevels evaluate. Confirmed
  `nix eval` realizes needed derivations on demand, so the CI eval job works on
  a fresh runner.
- **Still open:** B4 (tor→nftables), B5 (network-manager), B9 (strata libcuda),
  B13 (replace stale `docs/ivp-analysis.md`), B14 (confirm CI green on GitHub);
  IVP P2 (dead files), P3 (roles/system naming), P4 (flake helper), P5
  (masterpdfeditor), P6 (user groups), P7 (doc counts); H2/H4–H8; S1–S6
  (recipient scoping, backup encryption, restic); Phase 3–4.

### 2026-10-02 — IVP P4/P6/P7 + B13

- **P6:** new `users/common-groups.nix` computes `users.commonExtraGroups` from
  enabled services; the four user files now use
  `[ "users" ( "wheel" ) ] ++ config.users.commonExtraGroups` instead of a
  copy-pasted conditional block.
- **P4:** `flake.nix` extracts `commonModules` + a `mkHost configModule
  extraModules` helper; the three host definitions are one line each.
- **P7/B13:** corrected the syncthing counts (37 folders / 11 devices) in
  `README.md`, `services/syncthing/pool.nix`, `services/syncthing/default.nix`
  and `users/readmes/parents.md`; removed the stale `docs/ivp-analysis.md`.
- **Verification:** 129 files parse; with the `.nix` refactor alone (readmes
  held at HEAD) all three hosts evaluate to the *same* derivations as before
  (behavior-preserving). With the readme edits included the toplevel drv
  changes only because `parents.md` content feeds `systemd.services.home-readmes`;
  `nicky`/`sven` `extraGroups` still match the previous computed lists.
- **Still open:** B4, B5, B9, B14; IVP P2 (dead files), P3 (roles/system
  naming), P5 (masterpdfeditor); H2/H4–H8; S1–S6; Phase 3–4.

### 2026-10-02 — IVP P2/P5 + secrets S1/S2

- **P2/P5:** deleted 9 unimported/disabled modules; extracted the duplicated
  `masterpdfeditor` override into `packages/masterpdfeditor`.
- **S1:** dropped the global `all` union. Recips are now per-secret: system
  secrets + password hashes → `hosts`; each host's Syncthing device identity →
  that host only; `nicky.nix.age` → `user-nicky` + `hosts`. Verified decryption
  matrix; kids'/other users' keys can no longer read system secrets.
- **S2:** `agenix-backup.sh` now writes a passphrase-encrypted
  `.tar.gz.age` (`age -p`) instead of a plaintext tar of every key.
- **Rekey fix:** `agenix-rekey.sh` no longer uses `agenix -r` (which aborts on
  another host's device key); it rebuilds `hosts` then re-encrypts each secret
  to its declared recipients, skipping files this host cannot decrypt.
  End-to-end tested on a throwaway copy.
- **B5 resolved:** `wireless.enable` must stay `lib.mkForce true` — nixpkgs
  26.05's NM module sets it `true` for the DBus-controlled wpa_supplicant
  backend; `false` leaves no wpa_supplicant service and breaks Wi-Fi. The old
  "disable wpasupplicant" comment was wrong (corrected).
- **B4 deferred:** converting the Tor kid-block to a declarative
  `networking.nftables` chain needs explicit `users.users.<n>.uid` (null at eval
  → invalid `meta skuid { , }`); kept the iptables-nft activation and documented
  the requirement in `services/tor.nix`.
- **Still open:** B4 (blocked on explicit uids), B9 (strata libcuda), B14
  (confirm CI green on GitHub); IVP P3 (roles/system naming); H2/H4–H8;
  Phase 4 (restic backup).

### 2026-10-02 — CI action bump, service split, repo hygiene

- **CI:** bumped `DeterminateSystems/nix-installer-action` v4 → v23 (v4 is
  Node16-era and fails on current runners). Parse/lint/eval jobs unchanged.
- **P3:** split `services/system.nix` into `services/ananicy.nix` and
  `services/tailscale.nix` (one service per file, matching the repo), removing
  the `system.nix` name clash with `roles/system.nix`. Behavior-preserving.
- **H2/H6:** stopped tracking `.idea/` and the 18 MB `displaylink-580.zip`
  (`git rm --cached`, kept on disk) and added them to `.gitignore`.
- **H4/H5:** `apps/typst.nix` uses `environment.systemPackages` (not
  `config.…`); dropped the one-entry `kernels` indirection in `flake.nix`;
  removed unused `self`/`inputs@` from both flake `outputs`.
- **Verification:** 122 files parse; deadnix clean on changed files; all three
  hosts evaluate to the same known-good derivations. CI confirmed **green** on
  GitHub (run 37057440148: nix-parse + nix-lint + eval-hosts ×3 all succeeded).
- **Still open:** B4 (needs explicit stable uids), B9 (strata libcuda); H7
  (stale `result` symlinks); Phase 4 (restic).

### 2026-10-03 — Tor nftables (uids), strata libcuda gate, symlink cleanup

- **B4:** pinned explicit uids (nicky=1000, aeiuno=1001, sven=1002, aaron=1003)
  and converted the Tor kid-block to a declarative nftables output chain
  (`meta skuid { 1002, 1003 } ip daddr 127.0.0.1 tcp dport {9050,9051,9150}
  reject with tcp reset`). **Caveat:** NixOS never changes an existing user's
  uid (`update-users-groups.pl` keeps the old one and warns), so on
  already-installed hosts verify `getent passwd sven aaron` returns 1002/1003;
  if not, either set the config to the actual uids or migrate with `chown`,
  else the rule keys on the wrong uid.
- **B9:** `packages/strata/engine.nix` gained an `isCachyOS` argument (fed from
  `commonHm.isCachyOS` via `packages/strata/home.nix`); the
  `/usr/lib/libcuda.so.1` shim is now CachyOS-only. NixOS uses
  `/run/opengl-driver/lib` (autoAddDriverRunpath + a runtime `LD_LIBRARY_PATH`
  prepend), so a future NixOS reinstall of laptop-p16 works.
- **H7:** removed the stale `./result` and `./users/sven/result` symlinks.
- **Verification:** 122 files parse; uids render `1000-1003`; the nft chain
  renders `meta skuid { 1002, 1003 }`. (Full host eval was interrupted on
  request; re-run `nixos-rebuild test` on a host to confirm.)
- **Still open:** Phase 4 (restic backup).
