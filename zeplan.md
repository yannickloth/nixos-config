# zeplan — age host keys, secret audit, and server-nike bring-up

Status: implemented (2026-11-19); commit + verification gates pending (see §6).
Scope: make host age keys, secret recipients, and boot-time decryption explicit,
checked, and impossible to half-configure. Applies to every NixOS host, present
and future.

---

## 1. Incident that motivated this plan

`nixos-rebuild` on server-nike left all accounts unable to log in ("password
invalid"). Verified root cause, three independent defects:

1. **server-nike was never a recipient of any password secret.**
   The five `ssh-ed25519` stanzas in every `secrets/passwords/*.hash.age`
   decode to exactly `desktop-leto, laptop-hera, laptop-p16,
   laptop-travelmate, laptop-xps`. server-nike is absent.
2. `secrets.nix` carried `host-server-nike = "TODO_GENERATE_ON_FIRST_BOOT"` —
   a placeholder, not a key.
3. **Nothing detects this at build time.** The pinned agenix module
   (ryantm/agenix @ 5e5b88a) decrypts at *activation time* in the
   `agenix-install-secrets` sysinit unit. When no identity matches, the script
   prints a warning and continues (it ends with `true`). The build succeeds,
   `/run/agenix/password-*` is never created, `hashedPasswordFile` points at
   nothing, and logins fail silently.
4. Secondary: `hosts-eval` in `flake.nix` never evaluated server-nike, so CI
   had no coverage for the host.

Why the old bring-up model made this easy: the documented flow was "new host
generates its own SSH host key at first boot, then you copy the public key
into the repo and rekey". A fresh host therefore cannot decrypt anything
before a first boot without working logins. Chicken and egg.

---

## 2. Target design

### 2.1 Pinned host keys (key store is the source of truth)

A host's age keypair is **generated once in the key store**
(`ssh-keys/hosts/<host>{,.pub}`, gitignored, backed up in KeePassXC and
distributed by manual copy to each host and a USB stick — the current
practice), and the host **receives** it instead of generating its own.

Mechanics (verified against nixpkgs nixos-26.05 and Nix 2.35.5):

- **The build cannot ship the private key.** Nix's git-filtered flake source
  never sees gitignored files (verified empirically in a scratch repo: a
  staged-but-ignored file is invisible to `nix eval`; `git add -N` is
  impossible for ignored paths). So the private key is gitignored and is
  **placed on the host manually** as the documented bring-up step:
  `sudo install -m 0600 ssh-keys/hosts/<name> /etc/ssh/ssh_host_ed25519_key`.
- **The `.pub` IS tracked** in git (`!ssh-keys/hosts/*.pub` in
  `.gitignore`). It is public information (the same value lives in
  `secrets.nix`), and the build-time gates below need it inside the flake
  source. Nix applies the `.gitignore` rules committed at HEAD, so the
  tracked-`.pub` setup only takes effect once the `.gitignore` + `.pub`
  commit lands (the commit is therefore a prerequisite for the eval gates).
- `services.hostAge` pins `services.openssh.hostKeys` to the ed25519 entry
  at `/etc/ssh/ssh_host_ed25519_key` only. The nixpkgs `sshd-keygen` unit
  self-skips when the key file is non-empty (`ConditionFileNotEmpty=|!...`),
  so nothing is regenerated or drifted. RSA host key is dropped on pinned
  hosts (all clients are modern; ed25519 only).
- The pinned agenix module (ryantm/agenix @ 5e5b88a, `modules/age.nix`)
  derives `age.identityPaths` from `services.openssh.hostKeys`
  (ed25519/rsa entries), so the identity is
  `[ "/etc/ssh/ssh_host_ed25519_key" ]` with no extra wiring.

Consequences:

- A fresh install has **one manual pre-step** (copy the private key from the
  key store and install it in `/etc/ssh`), then `nixos-rebuild switch`.
  Login works on first boot because the key is in `/etc` before the agenix
  unit runs in sysinit — and if it is not there, gate 3 (below) fails loudly
  instead of locking the host out silently.
- The public key in `secrets.nix` and the key shipped to the host are the
  same file, checked at build time (below).
- Key-pair pairing (private key matches the tracked `.pub`) is checked
  where both files are visible: in the repo by `scripts/age-audit.sh repo
  ssh-keys`, and on the host by gate 3 (a wrong private key cannot decrypt,
  so the guard fails).

### 2.2 `services/host-age.nix` — one shared module for all hosts

Every NixOS host imports it once, pointing at its **tracked** public key:

```nix
{ services.hostAge = { enable = true; pubKey = ../../ssh-keys/hosts/<host>.pub; }; }
```

It provides, in order of the gate:

**a) Eval-time assertions** (the build aborts before anything is deployed;
each message names the fix):

| Check | Failure message (essence) |
|---|---|
| `pubKey` file exists in the flake source | `host-age: <path> does not exist. Generate the pair in the key store: ssh-keygen … and copy the private key to this host as /etc/ssh/ssh_host_ed25519_key` |
| `.pub` matches `^ssh-ed25519 [A-Za-z0-9+/]{68}(\s.*)?$` | `host-age: <path> is missing or not a well-formed ssh-ed25519 public key` |
| every value in `secrets.nix` is a well-formed ssh-ed25519 public key | `secrets.nix declares values that are not ssh-ed25519 public keys: <values>` — a placeholder like `TODO_*` is the exact 2026-11-19 bug, now fatal |
| the host's `.pub` is registered in `secrets.nix` (some secret lists it) | `host-age: <path> is not registered in secrets.nix — no secret lists it as a recipient` |
| every secret in `config.age.secrets` on this host is registered in `secrets.nix` **and** lists the host key in `publicKeys` | `host-age: one or more secrets this host consumes are not encrypted to its key: <list>` — run `scripts/agenix-rekey.sh`, commit, rebuild |
| `config.age.identityPaths` non-empty | `host-age: age.identityPaths is empty — services.openssh must be enabled` |

**b) Build-time recipient audit** (catches stale `.age` files — the other
half of the incident: files that were simply never re-encrypted after a key
change):

- A `runCommand` probe named `age-host-audit` runs on every build. For each
  secret in `config.age.secrets` it compares the recipient set inside the
  `.age` header against the `publicKeys` declared in `secrets.nix` and
  requires exact set equality.
- It is wired into the toplevel via
  `environment.etc."secrets/AGE_AUDIT_OK" = { source = <probe>; mode = "0644"; }`.
  The toplevel depends on the etc derivation, which depends on the probe, so
  **probe fails ⇒ toplevel build fails ⇒ `nixos-rebuild` aborts, nothing is
  deployed**.

Recipient identity algorithm (verified against the age 1.3.2 source,
`FiloSottile/age`, `agessh.sshFingerprint` + `internal/format`, and against
all five live keys in this repo):

```
fingerprint(pub)   = base64_raw( sha256( base64decode(pub_b64_field) )[:4] )
                     → 6 characters, no padding
file_recipients(f) = { 3rd token of every header line starting
                       "ssh-ed25519 " or "ssh-rsa " }
```

- `pub_b64_field` is the second field of the `ssh-ed25519 AAAA…` line.
- age writes this 4-byte SHA-256 prefix as the stanza argument so the
  decryptor can find its stanza fast; the authoritative check is decryption
  itself, but the fingerprint is exact for the set comparison (a 32-bit
  collision among ~7 family keys is not a realistic concern; a false match
  would at worst be caught again by real decryption at activation).
- Empirical verification (this repo, 2026-11-19):
  laptop-p16→`kG3jcA`, laptop-hera→`qrfZYA`, laptop-xps→`95FF0g`,
  laptop-travelmate→`krFEAA`, desktop-leto→`Ze1fYw` — all match the stanzas
  in `secrets/passwords/*.hash.age`.

**c) Activation-time loud guard** (last line, catches machine-key drift):

`systemd.services.age-secrets-guard` (oneshot, `sysinit.target`, after
`agenix-install-secrets.service`):

- every `config.age.secrets.<n>.path` exists under `/run/agenix` and is
  non-empty;
- every `password-*` path additionally matches `^$6$` (a valid SHA-512 crypt
  hash, not garbage);
- on any failure: names each missing/bad secret, explains the two possible
  causes (host key out of sync with `secrets.nix`; wrong key installed in
  `/etc/ssh`), names the fix (`scripts/agenix-rekey.sh`, then rebuild), and
  exits 1. The unit shows as failed in `systemctl` — the failure is loud and
  attributable, unlike agenix's own unit which ends with `true`.

### 2.3 Repo-wide audit — `scripts/age-audit.sh`

One script, two modes; used by the flake check and by humans:

```
age-audit.sh repo [KEYSTORE_DIR]
    - secrets.nix evaluates
    - every declared public key is well-formed ssh-ed25519
    - every declared secret file exists
    - per file: header recipient set == declared publicKeys set
      (missing → "not encrypted to X — rekey"; extra → "stale recipients")
    - if KEYSTORE_DIR given:
        * each host keypair is paired (ssh-keygen -y == .pub)
        * each secret is decryptable by at least one key-store key
          (age -d -i … >/dev/null)
age-audit.sh host SPEC_FILE
    - per spec line "<file> <pub> …": same set-equality check
      (no nix needed; used by the per-host build probe)
```

Exit code 0 = clean; non-zero with a per-secret report otherwise.

### 2.4 `scripts/agenix-rekey.sh` — identity fallback

The script's default identity is `/etc/ssh/ssh_host_ed25519_key`. On the
key-store machine (laptop-p16, currently running CachyOS) that is the wrong
key, and the script would silently re-encrypt nothing. New behavior:

- probe the default identity against the first existing secret;
- on failure, try each private key in `ssh-keys/hosts/` (skip `.pub`) until
  one decrypts, announce which identity it uses;
- if none works, fail with an explicit error instead of a no-op.

The existing removal guard (refuse to drop a host recipient without
`ALLOW_HOST_REMOVAL=1`) is unchanged.

### 2.5 CI (`flake.nix`)

- **`hosts-eval`: add server-nike** (currently missing — the reason nothing
  ever evaluated it).
- **New check `age-secrets`** (`runCommandLocal`, `cd ${self}`, like
  `parse-all`): runs `scripts/age-audit.sh repo`, plus the key-store section
  when `ssh-keys/` exists in the checkout (key-store machine / CI with keys).
- `scripts/age-audit.sh` added to the `scripts-syntax` check (bash -n +
  shellcheck).

### 2.6 Documentation

`secrets-structure/README.md` rewritten around the new model:

- key store = source of truth; keys are generated in the store, never on the
  host;
- "Adding a host" = the 5-step flow below;
- rekey now works from any machine that holds a key-store private key;
- the three failure gates (eval assertions, build-time audit, sysinit guard)
  and what each error message means;
- key distribution reality (manual copies per host + USB; KeePassXC is the
  canonical backup).

---

## 3. Per-host matrix and bring-up

| Host | Key in store | Pinned model | Notes |
|---|---|---|---|
| server-nike | **generated 2026-11-19** (this work) | yes | reinstall in progress; follows the new flow |
| laptop-p16 | verified (decrypts all password secrets) | yes | NixOS reinstall "quite soon"; currently standalone CachyOS (key-store machine) |
| laptop-hera | verified | yes | |
| laptop-xps | verified | yes | |
| desktop-leto | verified (added to store 2026-11-16; `ssh-keygen -y` matches `.pub`; decrypts its own syncthing identity + password secrets) | yes | |
| laptop-travelmate | spare key, no `nixosConfigurations` entry | n/a | recipient only |

**Bringing up a host (the canonical 5 steps):**

1. In the key store (any machine holding `ssh-keys/`):
   `ssh-keygen -t ed25519 -N "" -C "host <name>" -f ssh-keys/hosts/<name>`
2. `./scripts/agenix-rekey.sh` (no sudo on a key-store machine — the script
   falls back to the stored private keys automatically) — rebuilds the
   `hosts` group in `secrets.nix` from all of `ssh-keys/hosts/*.pub` and
   re-encrypts every host-scoped secret (the password hashes, syncthing GUI
   password, opencode keys, family SSH identities, per-host nix-serve keys,
   nicky's pg password) to the new full set. Do not run it on a machine
   holding only the NEW host's key: it cannot decrypt the existing secrets,
   and the removal guard refuses to drop recipients.
3. Commit `secrets.nix` + re-encrypted `.age` files +
   `ssh-keys/hosts/<name>.pub` (tracked) + the host's config wiring.
4. Host config: import `services/host-age.nix` with its `pubKey`, add the
   `nixosConfigurations` entry in `flake.nix`, and (new hosts) add it to
   `hosts-eval`.
5. Fresh install: NixOS installer → copy the repo checkout **plus
   `ssh-keys/hosts/<name>`** (the private key — gitignored, the only manual
   step) → `sudo install -m 0600 ssh-keys/hosts/<name> /etc/ssh/ssh_host_ed25519_key`
   → `nixos-rebuild switch`. Logins work on first boot; the build-time audit
   and the sysinit guard make any misconfiguration fail loudly instead of
   locking out.

server-nike's syncthing device identity (currently absent from
`secrets/syncthing/`) is generated **before** first boot (offline, ECDSA
P-256 self-signed cert/key — the same shape syncthing generates), encrypted
to the new host key, and committed, so the device ID is stable across
reinstalls and the repo audit sees no missing file.

---

## 4. server-nike storage: two encrypted SSDs, single boot prompt

Hardware (Dell Precision Tower 5810, from
`hosts/server-nike/hardware-configuration.nix`):

- **sdb (1.8 T):** `/boot` (vfat, unencrypted), LUKS root (btrfs: `/`,
  `/home`, `/nix`), LUKS swap.
- **sda (1.8 T):** LUKS data disk (btrfs) at `/data`, currently unlocked via
  a keyfile on the decrypted root
  (`fileSystems."/data".encrypted.keyFile = "/sysroot/root/.luks-keys/sda.key"`,
  `postMountCommand` runs `cryptsetup luksOpen --key-file` after `/` mounts).

Requirement: **both encrypted disks decrypt at boot in one step — one
password input, no second prompt, no keyfile prompt.**

### 4.1 Verified mechanism (systemd stage 1, `password-cache`)

`boot.initrd.luks.reusePassphrases` does **not** apply here: it is scripted
stage 1 only, and nixpkgs nixos-26.05 asserts "unsupported with systemd
stage 1" if it is set. The stage-1 mechanism is systemd's own passphrase
cache (crypttab option `password-cache`, default `yes`, added in systemd
v257; nixos-26.05 pins **systemd 261.2**):

- when a passphrase is typed for one device, systemd-cryptsetup caches it
  in the initrd's kernel keyring under the global key name
  `cryptsetup` (`src/cryptsetup/cryptsetup.c` `get_password`,
  `src/shared/ask-password-api.c` in the v260.5 source);
- every other device **checks the keyring before prompting**; concurrent
  waiters are woken by an inotify broadcast on
  `/run/systemd/ask-password/`, so parallel activation does not produce
  duplicate prompts;
- if the cached passphrase is rejected for a device, that device prompts
  on its own.

So: **the same passphrase on all LUKS containers + all of them in
`boot.initrd.luks.devices` = exactly one passphrase input at boot** — no
nixpkgs option needed, the default behavior provides it.

### 4.2 Target design

One passphrase (the root passphrase) unlocks all three LUKS containers:

| Container | Device (by-uuid, as in current config) | Where unlocked |
|---|---|---|
| root | `d32cf077-59d1-4de7-92b9-7010b525e41a` (sdb2) | initrd — the single prompt |
| swap | `697133b4-4e65-48b0-9077-b8b92df8b7b3` (sdb3) | initrd — reused passphrase |
| data | `da463042-ab85-4999-979b-91f70c7c17a7` (sda1) | initrd — reused passphrase |

Config (in `hosts/server-nike/hardware-configuration.nix`):

```nix
boot.initrd.luks = {
  # No option for the single prompt: systemd stage 1's password-cache
  # (default yes) handles it, see §4.1.
  devices = {
    "luks-d32cf077-…".device = "/dev/disk/by-uuid/d32cf077-…";
    "luks-697133b4-…".device = "/dev/disk/by-uuid/697133b4-…";
    data                  = { device = "/dev/disk/by-uuid/da463042-…"; };
  };
};
fileSystems."/data" = { device = "/dev/mapper/data"; fsType = "btrfs";
                        options = [ "compress=zstd" "noatime" ]; };  # no .encrypted wrapper
```

Why this over the current keyfile design:

- no loose file to recreate after a reinstall (the 2026-11-19 class of
  failure: state that exists only on a machine and nowhere else);
- the data disk keeps its own key slots, so the keyfile path remains a
  fallback (below);
- fully declarative — the whole boot is described in the repo.

### 4.3 Reinstall procedure (fresh disks — the planned path)

Run on the reinstall media / first boot of the fresh system, in order:

1. Root LUKS already formatted by the installer or `cryptsetup luksFormat`
   (choose the **root passphrase** deliberately — it is now the single boot
   secret for all three containers; record it in KeePassXC next to the host
   keys).
2. Data disk: `cryptsetup luksFormat /dev/disk/by-uuid/<sda1>` **with the
   same passphrase** as root. (If keeping the existing data disk instead of
   reformatting: `cryptsetup luksAddKey /dev/mapper/data` and enter the root
   passphrase as the new key — the data disk then accepts both its old
   passphrase/keyfile and the root passphrase.)
3. Swap disk: same passphrase (format or `luksAddKey`).
4. Rebuild with the config from §4.2.
5. **Verification (mandatory before the host is considered up):**
   - reboot; exactly **one** passphrase prompt; journal shows
     no second ask-password for the swap and data
      devices (`journalctl -b -1 | grep -i cryptsetup` shows all three
      cryptsetup units activating, swap and data from the cached passphrase);
   - `mount | grep /data` shows the btrfs mount; `/sync` bind mount present;
   - `systemctl status agenix-install-secrets age-secrets-guard` — both
     clean;
   - login with at least one family account and root (break-glass).

### 4.4 Keyfile fallback (kept, under secret management)

The data disk's keyfile key slot is kept (or re-added:
`cryptsetup luksAddKey /dev/mapper/data --key-file=<keyfile>`) as an
independent recovery path in case the root passphrase is ever lost. The
keyfile itself enters the repo encrypted to the host key:

- `secrets/luks/server-nike-data.key.age` (recipients: `hosts`),
- one-time manual step after any root reinstall:
  `sudo age -d -i /etc/ssh/ssh_host_ed25519_key -o /root/.luks-keys/sda.key secrets/luks/server-nike-data.key.age`
- keyfile backup in KeePassXC/USB with the other keys.

This step is documented in the README's server-nike reinstall section.

---

## 5. Risks and accepted trade-offs

| Item | Decision |
|---|---|
| RSA host key dropped on pinned hosts (ed25519 only) | accepted — all clients are modern OpenSSH; keeps the sshd-keygen self-skip clean |
| Private key is gitignored, so its placement on a fresh host is one manual step the build cannot perform | accepted — Nix's git-filtered source cannot carry ignored files (verified); the cost is contained: a missing/wrong placed key fails gate 3 loudly at sysinit instead of locking the host out silently |
| `password-cache` keeps the boot passphrase in the initrd's kernel keyring during boot | accepted — systemd's default and documented behavior (the keyring dies with the boot); the alternative (per-device prompts) violates the single-step requirement |
| Root passphrase is now the single boot secret for 3 containers | accepted — it is a strong passphrase in KeePassXC; the data disk's keyfile key slot is the independent fallback |
| `ssh-keys/` distributed by manual copy (hosts + USB) | current practice, documented; KeePassXC is the canonical recovery copy; a syncthing folder for `ssh-keys/` is a possible later improvement, not in scope |
| 32-bit age fingerprint in the audit | sufficient for set comparison among ~7 family keys; authoritative decryption still happens at activation and is guarded by `age-secrets-guard` |

---

## 6. Execution order and verification gates

1. `scripts/age-audit.sh` (repo + host modes)
2. `services/host-age.nix`
3. Host wirings: server-nike, laptop-p16, laptop-hera, laptop-xps,
   desktop-leto
4. server-nike syncthing identity: generate offline → encrypt to the new
   host key → commit (fills `secrets/syncthing/server-nike/`)
5. `secrets.nix`: `host-server-nike` placeholder → real public key (done
   via step 7's rekey, which rewrites the `hosts` group with the real key
   values); also fold in `pg-nicky-password.age`, which was consumed on the
   hosts but never registered
6. `scripts/agenix-rekey.sh`: identity fallback
7. Run rekey from the key-store machine (exercises the fallback: this
   machine's `/etc/ssh` key is the CachyOS key, not a store key)
8. `flake.nix`: server-nike in `hosts-eval`, `age-secrets` check,
   `scripts-syntax` entry
9. `hosts/server-nike/hardware-configuration.nix`: §4.2 LUKS design
10. `secrets-structure/README.md` rewrite + stale-comment fixes
    (`flake.nix` p16/CachyOS note, `secrets.nix` header, syncthing
    "KeePassXC" comment)
11. **Commit** (`.gitignore` + tracked `ssh-keys/hosts/*.pub` + all of the
    above), then **push**

**Commit precedes verification.** Nix 2.35.5 applies the `.gitignore`
rules committed at HEAD to the flake source, so the tracked `.pub` files
are invisible to `nix eval` until the `.gitignore` + `.pub` commit lands.
The host-eval gates below therefore run after the commit; if a gate fails,
fix in a follow-up commit and push that too.

Verification gates (all must pass before "done"):

- `nix flake check --flake .` — parse-all, hosts-eval (now incl.
  server-nike), age-secrets, scripts-syntax, existing checks
- `scripts/age-audit.sh repo ssh-keys` clean
- each host's toplevel evaluates; the per-host audit probe builds
- negative tests (must fail loudly): a secrets.nix value changed to
  `TODO_TEST` → eval assertion fires; a password `.age` re-encrypted to a
  wrong key set → build-time audit fires
- server-nike reinstall: §4.3 verification checklist green
