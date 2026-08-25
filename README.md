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

Currently, no specific tool is used to manage secrets. They are either hashed in the `.nix` files, or not included in this repo.

### CIFS

CIFS **client** mounts each use their own credentials file under `secrets/cifs/`
(see `secrets-structure/README.md`). For the nestor mount, place
`username=…`/`password=…` in `secrets/cifs/nestor.secrets` (gitignored);
`services/secrets.nix` provisions it to `/etc/nixos/cifs/nestor.secrets`,
which `services/cifs-nestor.nix` reads:

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
- **Web UI**: `http://<host>:8384`, single shared login — user `nicky`, password
  in `/etc/secrets/syncthing-gui-password` (Syncthing has one GUI account)
- **Device identity**: cert/key auto-provisioned into
  `/etc/nixos/secrets/syncthing/<host>/` by the activation script. The device
  **IDs** are committed in `pool.nix`, but the private **cert/key** stay out of
  git — back them up in KeePass and place them at that path on a fresh host to
  keep its device ID stable.

### AI chat

Family AI chat (Open WebUI) runs on every host at `http://localhost:8080`
(`services/ai-chat.nix`). Providers are OpenAI-compatible; base URLs are kept in
git, API keys in the gitignored `secrets/open-webui.env` (see
`secrets-structure/README.md` and `/etc/secrets/README.md`):

| Provider | Base URL |
| --- | --- |
| DeepSeek | `https://api.deepseek.com` |
| Kimi for Coding | `https://api.kimi.com/coding/v1` |
| Hetzner AI | `https://inference.hetzner.com/api/v1` |


## External resources used for this config

### nixos-hardware

The project https://github.com/NixOS/nixos-hardware is used as a channel to provide specific config for hardware devices.

