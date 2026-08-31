# Infolead NixOS configuration

## Flake
The config uses the nix flake feature.

### Update

To update packages
1. Inside the root directory of this project, run `nix flake update`. This will update the `flake.lock` file.
2. In the same directory, run `sudo nixos-rebuild switch --flake ./`. This will automatically detect the flake and use the flake feature. (TODO: check whether the --upgrade has any impact when the config is a flake). (TODO adapt the command with the parameters to specify another location of the config files if they are not inside `/etc/nix`).

Et voilà!

## Family shared folders & permissions

- `/steamlib` — shared Steam library (`games/steam.nix`): `steam` group
  (parents) read-write, kids read-only (play, not modify).
- `/sync` — Syncthing data (`services/syncthing/`): parents only; kids
  blocked by default, per-folder `kids`-group ACL whitelist later.
- `/filedrop` — family drop folder (`users/filedrop.nix`): all accounts
  read-write (no sticky bit), `~/filedrop` symlink in every home, plus a
  `filedrop` Samba share (`services/samba.nix`).

## Secrets

Secrets are managed with **agenix** (age-encrypted files committed to git).
Encrypted `.age` files live in `secrets/`; the recipient SSH public keys are
listed in `secrets.nix`. Private keys stay on each machine (backed up in
KeePassXC). See `secrets-structure/README.md` for the full workflow (key
inventory, editing, new-host bring-up, rekey, backup).

### CIFS

CIFS **client** mounts each use their own credentials file under `secrets/cifs/`
(see `secrets-structure/README.md`). For the nestor mount, provision the
credentials as an agenix secret that decrypts to `/etc/nixos/cifs/nestor.secrets`
(read by `services/cifs-nestor.nix`):

```ini
username=xxx
password=xxx
```

> Samba **server** shares (`services/samba.nix`) authenticate each client with
> its own OS account (`"valid users"` per share + `smbpasswd`); the CIFS
> credentials files above are only for mounting remote shares.

### Syncthing

Syncthing runs as a single system service on every host (`services/syncthing/`),
syncing all 34 folders (see `services/syncthing/pool.nix`) to nestor and the
other laptops as replication / closest-to-backup. Each host only sets
`services.syncthing.self` to its device name; folders, devices and per-host
identity are derived automatically.

- **Data**: `/sync` (group `syncthing` = nicky + aeiuno; kids blocked)
- **Web UI**: `http://<host>:8384`, single shared login — username set via the
  `services.syncthing.guiUser` option (default `nicky`), password decrypted from
  `secrets/syncthing-gui-password.age` to `/etc/secrets/syncthing-gui-password`
- **Device identity**: cert/key decrypted from
  `secrets/syncthing/<host>/*.age` to `/etc/nixos/secrets/syncthing/<host>/` by
  agenix. Device **IDs** are committed in `pool.nix`; the private **cert/key**
  are committed only as encrypted `.age` files. Back the host's SSH key up in
  KeePassXC so a fresh host keeps its device ID stable.

### AI chat

Family AI chat (Open WebUI) runs on every host at `http://localhost:8080`
(`services/ai-chat.nix`). Providers are OpenAI-compatible; base URLs are kept in
git, API keys decrypted from `secrets/open-webui.env.age` to
`/etc/secrets/open-webui.env` (see `secrets-structure/README.md`):

| Provider | Base URL |
| --- | --- |
| DeepSeek | `https://api.deepseek.com` |
| Kimi for Coding | `https://api.kimi.com/coding/v1` |
| Hetzner AI | `https://inference.hetzner.com/api/v1` |


## External resources used for this config

### nixos-hardware

The project https://github.com/NixOS/nixos-hardware is used as a channel to provide specific config for hardware devices.

