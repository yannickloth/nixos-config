# Secrets management with agenix

This config uses [agenix](https://github.com/ryantm/agenix) to manage secrets:
age-encrypted files committed to git. Private keys never leave the machines they
belong to (plus a KeePassXC backup for reinstall recovery).

## Model (deliberately simple)

- **Encrypted `.age` files** live in `secrets/` and are committed to git.
- **Recipients** are SSH public keys — one per host (`ssh-keys/hosts/`) and one
  per user (`ssh-keys/users/`).
- **Union strategy:** every `.age` file is encrypted to **all** recipients, so
  any host or user can decrypt anything. This is the most automatic setup — no
  per-host targeting to maintain.
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
- `scripts/agenix-rekey.sh` — regenerate the recipient union + re-encrypt.
- `scripts/agenix-backup.sh` — package private keys into a backup archive.

## Editing a secret

```sh
# On a machine that has a private key for one of the recipients:
nix run nixpkgs#agenix -- -e secrets/<name>.age
# If the default key doesn't match, pass -i with a private key you hold.
```

## Adding a new host (bring-up)

A fresh NixOS host generates its own `/etc/ssh/ssh_host_ed25519_key`. To let it
decrypt secrets:

1. Get its public key: `cat /etc/ssh/ssh_host_ed25519_key.pub` (or read it
   after first install).
2. Add it as a recipient in `secrets.nix` (or run the rekey script on that host).
3. `agenix -r` to re-encrypt all `.age` files to the new union.
4. Commit `secrets.nix` + the re-encrypted `.age` files.

For a host that has a **syncthing identity** you want to keep, also drop its
`cert.pem`/`key.pem` into `secrets/syncthing/<host>/` (encrypted to the union)
so the device ID is preserved. If the host has no syncthing identity yet, the
module skips the cert/key and syncthing generates its own on first boot.

## Adding a host/user key (automated)

```sh
# generate the key (for a new host or user)
ssh-keygen -t ed25519 -N "" -C "host <name>" -f ssh-keys/hosts/<name>

# regenerate the union + re-encrypt
./scripts/agenix-rekey.sh

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

## Threats / notes

- age is **not post-quantum safe**; keys are long-lived, so keep them strong and
  rotate periodically if the threat model warrants it (see the agenix README).
- The union strategy trades per-host isolation for simplicity: any compromised
  private key can decrypt everything. Acceptable given the goal of a quick,
  uniform, fully-automatic setup. If you need isolation later, narrow the
  `publicKeys` per secret.
