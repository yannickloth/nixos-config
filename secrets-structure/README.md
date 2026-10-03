# Secrets management with agenix

This config uses [agenix](https://github.com/ryantm/agenix) to manage secrets:
age-encrypted files committed to git. Private keys never leave the machines they
belong to (plus a KeePassXC backup for reinstall recovery).

## Model (deliberately simple)

- **Encrypted `.age` files** live in `secrets/` and are committed to git.
- **Recipients** are SSH public keys — one per host (`ssh-keys/hosts/`) and one
  per user (`ssh-keys/users/`).
- **Per-secret scoping (no global union):** each `.age` file is encrypted only
  to the keys that must decrypt it (see the strategy note in `secrets.nix`):
  - host-wide system secrets (Syncthing GUI password, Open WebUI keys) and the
    user password hashes → the host keys (`hosts`);
  - a host's Syncthing device identity → that host's key only;
  - nicky's personal API keys → `user-nicky` + the host keys (for recovery).
  A kid's (or another user's) key therefore cannot read a secret it has no
  business reading.
- **Decryption** happens on the machine at activation, using that machine's
  private key (NixOS hosts use `/etc/ssh/ssh_host_ed25519_key` automatically;
  home-manager uses the user's key). Nothing is decrypted into the Nix store.

## Key inventory

| Entity | Private key | Installed at | Decrypts |
|--------|-------------|--------------|----------|
| host `laptop-*` | `ssh-keys/hosts/<host>` | `/etc/ssh/ssh_host_ed25519_key` on that host | system secrets |
| user `nicky` | `ssh-keys/users/nicky` | `~/.ssh/agenix_nicky` | nicky's home-manager secrets |

**Backup rule:** all private keys in `ssh-keys/` are backed up in **KeePassXC**
(see `scripts/agenix-backup.sh`). On reinstall, restore the key to its machine to
keep decrypting and to preserve the syncthing device identity.

## Files

- `secrets.nix` — agenix CLI recipient config (NOT imported into the system).
- `secrets/*.age` — the encrypted secrets (committed).
- `secrets-structure/*.example` — example plaintext formats for reference.
- `ssh-keys/` — private keys (gitignored, backed up in KeePassXC).
- `scripts/agenix-rekey.sh` — regenerate the `hosts` group + re-encrypt.
- `scripts/agenix-backup.sh` — package private keys into a passphrase-encrypted archive.

## Editing a secret

```sh
# On a machine that has a private key for one of the recipients:
nix run nixpkgs#agenix -- -e secrets/<name>.age
# If the default key doesn't match, pass -i with a private key you hold.
```

## Passwords (declarative, host-key scoped)

`users.mutableUsers = false`: accounts are owned by the config, so users cannot
change their own password (a `passwd` change is reverted on the next
activation). The per-user and `root` password **hashes** live in
`secrets/passwords/<user>.hash.age`, encrypted to the host keys only, and are
consumed by `users/passwords.nix` via `hashedPasswordFile`. Parents rotate a
password by editing the secret and rebuilding:

```sh
mkpasswd -m sha-512                 # copy the new hash
# A password secret is encrypted to the HOST keys only, so decrypting it needs
# a host key (root):
sudo ./scripts/agenix-rekey.sh
# or: sudo agenix -e -i /etc/ssh/ssh_host_ed25519_key secrets/passwords/<user>.hash.age
```

`root` is the local break-glass administrator (console/recovery); wheel users
reach root through passwordless `sudo`, and root SSH login is disabled entirely
(`PermitRootLogin = "no"`, `services/openssh.nix`).

## Adding a new host (bring-up)

A fresh NixOS host generates its own `/etc/ssh/ssh_host_ed25519_key`. To let it
decrypt secrets:

1. Get its public key: `cat /etc/ssh/ssh_host_ed25519_key.pub` (or read it
   after first install).
2. Drop its public key into `ssh-keys/hosts/<host>.pub` (gitignored).
3. On an **existing** host that holds a current host key, run
   `sudo ./scripts/agenix-rekey.sh` — it rebuilds the `hosts` group in
   `secrets.nix` from `ssh-keys/hosts/*.pub` and re-encrypts the host-scoped
   secrets to include the new host. Do **not** run it on the new host: it cannot
   decrypt the existing secrets, and the script refuses to drop recipients.
4. Commit `secrets.nix` + the re-encrypted `.age` files.

For a host that has a **syncthing identity** you want to keep, also drop its
`cert.pem`/`key.pem` into `secrets/syncthing/<host>/` (encrypted to that host's
key) so the device ID is preserved. If the host has no syncthing identity yet,
the module skips the cert/key and syncthing generates its own on first boot.

## Adding a host/user key (automated)

```sh
# generate the key (for a new host or user)
ssh-keygen -t ed25519 -N "" -C "host <name>" -f ssh-keys/hosts/<name>

# regenerate the `hosts` group + re-encrypt (run on an existing host)
sudo ./scripts/agenix-rekey.sh

# back up the new private key in KeePassXC
./scripts/agenix-backup.sh
```

## Runtime paths

The decrypted secrets are mounted at the paths services already expect:

| Secret | `.age` file | Mounted at |
|--------|-------------|------------|
| Syncthing web-UI password | `secrets/syncthing-gui-password.age` | `/etc/secrets/syncthing-gui-password` |
| Open WebUI provider keys | `secrets/open-webui.env.age` | `/etc/secrets/open-webui.env` |
| Syncthing device cert (per host) | `secrets/syncthing/<host>/cert.pem.age` | `/etc/nixos/secrets/syncthing/<host>/cert.pem` |
| Syncthing device key (per host) | `secrets/syncthing/<host>/key.pem.age` | `/etc/nixos/secrets/syncthing/<host>/key.pem` |
| nicky's AI API keys (home-manager) | `secrets/nicky.nix.age` | `$XDG_RUNTIME_DIR/agenix/nicky.nix` |
| User login password hashes | `secrets/passwords/<user>.hash.age` | `/run/agenix/password-<user>` |
| root break-glass password | `secrets/passwords/root.hash.age` | `/run/agenix/password-root` |

## Threats / notes

- age is **not post-quantum safe**; keys are long-lived, so keep them strong and
  rotate periodically if the threat model warrants it (see the agenix README).
- Secrets are scoped per recipient set (no global union), so a compromised key
  only exposes the secrets encrypted to it: a host key exposes the host-scoped
  system secrets and password hashes; a user key only that user's own secrets.
  Keep the host keys root-only (they are `/etc/ssh/ssh_host_ed25519_key`).
