# Secrets management with agenix

This config uses [agenix](https://github.com/ryantm/agenix) to manage secrets:
age-encrypted files committed to git. Private keys are generated in the repo
key store, distributed by manual copy, and backed up in KeePassXC.

## Why this model (2026-11-19 server-nike lockout)

The old bring-up flow was: a fresh host generates its own SSH host key at
first boot, then its public key is copied into the repo and the secrets are
re-keyed. That made a chicken-and-egg state easy to build and impossible to
detect: server-nike was never a recipient of any password secret,
`secrets.nix` carried a `TODO_*` placeholder for its key, and the build
succeeded anyway — agenix decrypts at *activation* and swallows failures, so
the rebuild finished cleanly and every account on the host was locked out
with "password invalid".

The new model removes both holes:

- **Host keys are generated in the repo key store, not on the host.** A host
  receives its keypair; it never generates its own (the pinned
  `services.openssh.hostKeys` makes `sshd-keygen` self-skip, and the build
  checks the key is the one from the store).
- **Three failure gates** (below) make a stale or missing recipient set fail
  the BUILD, not the boot.

## Model

- **Encrypted `.age` files** live in `secrets/` and are committed to git.
- **Recipients** are SSH public keys — one per host (`ssh-keys/hosts/`) and
  one per user (`ssh-keys/users/`).
- **Key store = source of truth.** Keypairs are generated in
  `ssh-keys/hosts/<host>{,.pub}` and `ssh-keys/users/<user>{,.pub}`. The
  private keys are gitignored and distributed by manual copy to each host
  and a USB stick (current practice); **KeePassXC is the canonical backup**.
  The `ssh-keys/hosts/*.pub` files ARE tracked in git: they are public
  information (the same values live in `secrets.nix`), and Nix's
  git-filtered flake source cannot see ignored files, so the build-time
  audits below need the `.pub` files inside the flake source.
- **Per-secret scoping (no global union):** each `.age` file is encrypted
  only to the keys that must decrypt it (see the strategy note in
  `secrets.nix`):
  - host-wide system secrets (Syncthing GUI password, opencode provider keys,
    PostgreSQL role password) and the user password hashes → the host keys
    (`hosts`);
  - a host's Syncthing device identity → that host's key only;
  - nicky's personal API keys → `user-nicky` + the host keys (recovery).
  A kid's (or another user's) key cannot read a secret it has no business
  reading.
- **Pinned host identity.** On every NixOS host,
  `services/host-age.nix` pins `services.openssh.hostKeys` to the ed25519
  key. The private half is placed at `/etc/ssh/ssh_host_ed25519_key`
  (mode 0600) as part of bring-up (below); the pinned agenix module then
  uses it as the `age` identity with no extra wiring.
- **Decryption** happens on the machine at activation, using that machine's
  private key (NixOS hosts: `/etc/ssh/ssh_host_ed25519_key`; home-manager:
  the user's key). Nothing is decrypted into the Nix store.

## The three failure gates

All three are provided by `services/host-age.nix` (imported once per host)
plus `scripts/age-audit.sh`.

| Gate | When | Catches | On failure |
|------|------|---------|------------|
| 1. Eval-time assertions | `nix eval`/any build of the host | placeholder values in `secrets.nix` (the exact 2026-11-19 bug); the host's `.pub` missing/malformed or not registered in `secrets.nix`; any secret the host consumes not encrypted to its key | the build aborts with a message naming the fix |
| 2. Build-time recipient audit | toplevel build (`environment.etc."secrets/AGE_AUDIT_OK"`) | stale `.age` files: the recipients inside the file header differ from the `publicKeys` declared in `secrets.nix` | the toplevel build fails; `nixos-rebuild` aborts, nothing is deployed |
| 3. Activation guard (`age-secrets-guard`) | every boot, sysinit | a private key in `/etc/ssh` that cannot decrypt (wrong key, missing key) — the case the build cannot see, because the private key is gitignored | the unit fails loudly, naming each broken secret and the fix; logins stay broken until fixed (instead of silently, as before) |

Gate 2 compares 6-character age fingerprints (see `scripts/age-audit.sh`
header); the authoritative check is decryption itself, which gate 3 covers.

## Why a successful build is not a login guarantee

The build phase of `nixos-rebuild` only reads the flake source — the
committed git tree. The private key is gitignored by design (Nix's
git-filtered source can never see ignored files), so no build, on any
machine, can check `/etc/ssh/ssh_host_ed25519_key` on the host. Gates 1–2
therefore verify the **public** half: the tracked `.pub` is well-formed and
registered in `secrets.nix`, and every secret the host consumes is
encrypted to it. A green build means "if the key is installed, this host
will decrypt" — nothing more.

The machine side is verified outside the build, in two places:

- **Before the reboot** — `scripts/preboot-key-check.sh`, run as root on
  the host from a checkout that contains the gitignored `ssh-keys/`
  directory (the copy made from the key-store machine, not a fresh clone):
  ```sh
  sudo scripts/preboot-key-check.sh
  ```
  It verifies that the installed key exists with the right permissions,
  pairs with the tracked `.pub`, and decrypts every password secret. If
  `age` is not on PATH it fetches it via `nix build nixpkgs#age` (needs
  flake support + network — the same prerequisites as the rebuild).
- **At every boot** — gate 3 (`age-secrets-guard`), which fails loudly and
  names each broken secret in the journal if agenix could not decrypt.

What happens if a flake system boots without the key installed (verified
against nixpkgs nixos-26.05, `sshd-keygen`): the unit sees
`/etc/ssh/ssh_host_ed25519_key` missing or empty and generates a **new
random** host key there; from then on it self-skips because the file is
non-empty. agenix uses that key as its identity, matches no recipient,
decrypts nothing, and every password login fails on every boot — the
2026-11-19 server-nike incident. Gate 3 fails on each boot and names the
fix, and the previous entry in the systemd-boot menu stays selectable, so
the machine is recoverable; the pre-flight exists so you never pay for the
build and the reboot to find out.

**Operational rule:** on any fresh host, install the key and pass
`scripts/preboot-key-check.sh` before the first flake rebuild or reboot. A
green build never substitutes for this check.

## Files

- `secrets.nix` — agenix CLI recipient config (NOT imported into the system).
- `secrets/*.age` — the encrypted secrets (committed).
- `secrets-structure/*.example` — example plaintext formats for reference.
- `ssh-keys/hosts/*.pub` — host public keys (tracked).
- `ssh-keys/` — private keys (gitignored, backed up in KeePassXC).
- `services/host-age.nix` — the pinned-identity module + gates 1–3.
- `scripts/age-audit.sh` — repo-wide recipient/keypair/decryptability audit.
  `repo` mode (recipient sets) runs in the `age-secrets` flake check on every
  machine; with a key-store argument (`repo ssh-keys`) it additionally checks
  keypair pairing and decryptability — that part needs the gitignored private
  keys, so it runs only on the key-store machine (run it after every rekey).
  `host` mode runs in the per-host build probe.
- `scripts/preboot-key-check.sh` — machine-side pre-boot check: installed key
  present with right permissions, pairs with the tracked `.pub`, decrypts the
  password secrets. Run before the first flake rebuild of a fresh host
  ("Why a successful build is not a login guarantee" above).
- `scripts/agenix-rekey.sh` — rebuild the `hosts` group + re-encrypt.
- `scripts/agenix-backup.sh` — package private keys into a passphrase-encrypted archive.

## Editing a secret

```sh
# On a machine that has a private key for one of the recipients
# (a key-store machine works with any of the stored keys):
nix run nixpkgs#agenix -- -e secrets/<name>.age
# If the default key doesn't match, pass -i with a private key you hold.
# Then run scripts/agenix-rekey.sh (or re-encrypt the one file to its
# declared recipients) so the file header matches secrets.nix again.
```

## Passwords (declarative, host-key scoped)

`users.mutableUsers = false`: accounts are owned by the config, so users
cannot change their own password (a `passwd` change is reverted on the next
activation). The per-user and `root` password **hashes** live in
`secrets/passwords/<user>.hash.age`, encrypted to the host keys only, and
are consumed by `users/passwords.nix` via `hashedPasswordFile`. Parents
rotate a password by editing the secret and rebuilding:

```sh
mkpasswd -m sha-512                 # copy the new hash
# A password secret is encrypted to the HOST keys only, so decrypting it
# needs a host key (on a key-store machine, any stored host key works):
./scripts/agenix-rekey.sh
# or: agenix -e -i ssh-keys/hosts/<any> secrets/passwords/<user>.hash.age
```

`root` is the local break-glass administrator (console/recovery); wheel
users reach root through passworded `sudo` (15-minute cache after first
auth), and root SSH login is disabled entirely
(`PermitRootLogin = "no"`, `services/openssh.nix`).

## Adding a new host (bring-up)

The canonical five steps. The only manual key handling is step 5 (copy the
private key to the host) — the same manual step as before, but the key now
comes from the store instead of being generated on the machine.

1. **In the key store** (any machine holding `ssh-keys/`), generate the
   keypair:
   ```sh
   ssh-keygen -t ed25519 -N "" -C "host <name>" -f ssh-keys/hosts/<name>
   ```
2. **Rekey** on any machine that holds a key-store private key (the script
   falls back to the stored keys automatically; no sudo needed there):
   ```sh
   ./scripts/agenix-rekey.sh
   ```
   It rebuilds the `hosts` group in `secrets.nix` from
   `ssh-keys/hosts/*.pub` and re-encrypts every host-scoped secret to the
   full set. Do not run it on a machine holding only the NEW host's key:
   it cannot decrypt the existing secrets, and the removal guard refuses to
   drop recipients.
3. **Commit** `secrets.nix` + the re-encrypted `.age` files +
   `ssh-keys/hosts/<name>.pub` (tracked).
4. **Wire the host**: import `../../services/host-age.nix` in its host file
   with `services.hostAge = { enable = true; pubKey = ../../ssh-keys/hosts/<name>.pub; };`,
   add the `nixosConfigurations` entry in `flake.nix`, and add the host to
   `hosts-eval` in the checks.
5. **Fresh install**: NixOS installer → copy the repo checkout **plus
   `ssh-keys/hosts/<name>`** (the private key — gitignored, the only manual
   key step) and place it **before the first `nixos-rebuild` of the new
   config**, then pass the pre-flight check:
   ```sh
   sudo install -m 0600 ssh-keys/hosts/<name> /etc/ssh/ssh_host_ed25519_key
   sudo scripts/preboot-key-check.sh
   ```
   The check passes only if the installed key pairs with the tracked `.pub`
   and actually decrypts the password secrets. **A successful build does not
   prove any of this** — the build cannot see `/etc/ssh` (see "Why a
   successful build is not a login guarantee"). Logins work on first boot:
   the key is in `/etc` before the agenix unit runs in sysinit, and the
   gates above make any misconfiguration fail loudly instead of locking the
   host out.

For a host with a **syncthing identity** you want to keep, commit its
`cert.pem`/`key.pem` (encrypted to that host's key) into
`secrets/syncthing/<host>/` before first boot — for a brand-new host,
pre-generate the identity offline (ECDSA P-256 self-signed, same shape as
syncthing's own) so the device ID is stable across reinstalls. Without a
committed identity, syncthing generates its own on first boot.

## Reinstalling a host

1. Restore the host's private key from the key store (or the KeePassXC
   backup if the store copy is lost):
   ```sh
   sudo install -m 0600 ssh-keys/hosts/<host> /etc/ssh/ssh_host_ed25519_key
   ```
   before the first `nixos-rebuild` of the new config, then run
   `sudo scripts/preboot-key-check.sh` — a green build does not check the
   installed key (see "Why a successful build is not a login guarantee").
2. Rebuild. The syncthing device identity and every secret come from the
   committed `.age` files; nothing is regenerated.

## Runtime paths

The decrypted secrets are mounted at the paths services already expect:

| Secret | `.age` file | Mounted at |
|--------|-------------|------------|
| Syncthing web-UI password | `secrets/syncthing-gui-password.age` | `/etc/secrets/syncthing-gui-password` |
| opencode provider keys | `secrets/opencode-keys.env.age` | `/etc/secrets/opencode-keys.env` |
| Syncthing device cert (per host) | `secrets/syncthing/<host>/cert.pem.age` | `/etc/nixos/secrets/syncthing/<host>/cert.pem` |
| Syncthing device key (per host) | `secrets/syncthing/<host>/key.pem.age` | `/etc/nixos/secrets/syncthing/<host>/key.pem` |
| nicky's AI API keys (home-manager) | `secrets/nicky.nix.age` | `$XDG_RUNTIME_DIR/agenix/nicky.nix` |
| PostgreSQL `nicky` role password | `secrets/pg-nicky-password.age` | `/run/agenix/pg-nicky-password` (system), `$XDG_RUNTIME_DIR/agenix/pg-nicky-password` (home-manager) |
| User login password hashes | `secrets/passwords/<user>.hash.age` | `/run/agenix/password-<user>` |
| root break-glass password | `secrets/passwords/root.hash.age` | `/run/agenix/password-root` |

The PostgreSQL password is the one secret whose **plaintext** is kept
locally, at `ssh-keys/users/pg-nicky-password.txt` (gitignored, like the
private keys), so it can be pasted into Datagrip/JetBrains when setting up
a connection. It is also in `~/.pgpass` on every host, which the activation
writes from the decrypted secret. Constraints, enforced by
`services/postgresql.nix`: one line, no `:` — that is the `~/.pgpass`
format, and a value with either is rejected rather than silently truncating
the client's credentials.

## server-nike: LUKS data-disk keyfile

server-nike's `/data` LUKS disk unlocks at boot with the same passphrase as
root (single boot prompt, see `zeplan.md` §4). Its keyfile key slot is kept
as an independent recovery path in case the root passphrase is ever lost:
the keyfile lives in the repo encrypted to the host keys as
`secrets/luks/server-nike-data.key.age` and is decrypted to
`/root/.luks-keys/sda.key` once after each reinstall:

```sh
sudo age -d -i /etc/ssh/ssh_host_ed25519_key -o /root/.luks-keys/sda.key \
  secrets/luks/server-nike-data.key.age
```

Keep a copy of the keyfile in KeePassXC/USB with the other keys.

## Threats / notes

- age is **not post-quantum safe**; keys are long-lived, so keep them strong
  and rotate periodically if the threat model warrants it (see the agenix
  README).
- Secrets are scoped per recipient set (no global union), so a compromised
  key only exposes the secrets encrypted to it: a host key exposes the
  host-scoped system secrets and password hashes; a user key only that
  user's own secrets. Keep the host keys root-only
  (they are `/etc/ssh/ssh_host_ed25519_key`, mode 0600).
- `ssh-keys/` is distributed by manual copy (each host + a USB stick).
  That is the current practice and the only part of this scheme that is
  not automated; KeePassXC is the canonical recovery copy.
