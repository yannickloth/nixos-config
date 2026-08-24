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
- `/sync` — Syncthing data (`services/syncthing.nix`): parents only; kids
  blocked by default, per-folder `kids`-group ACL whitelist later.
- `/filedrop` — family drop folder (`users/filedrop.nix`): all accounts
  read-write (no sticky bit), `~/filedrop` symlink in every home, plus a
  `filedrop` Samba share (`services/samba.nix`).

## Secrets

Currently, no specific tool is used to manage secrets. They are either hashed in the `.nix` files, or not included in this repo.

### CIFS

This config needs a file named `smb-secrets` in the root directory of this project containing your username and password in clear-text:

1. Run `touch smb-secrets`

2. Open this file and add your credentials:
```ini
username=xxx
password=xxx
```


## External resources used for this config

### nixos-hardware

The project https://github.com/NixOS/nixos-hardware is used as a channel to provide specific config for hardware devices.

