# Infolead NixOS configuration

## Flake
The config uses the nix flake feature.

### Update

To update packages
1. Inside the root directory of this project, run `nix flake update`. This will update the `flake.lock` file.
2. Run `nixos-rebuild switch`. This will automatically detect the flake and use the flake feature. (TODO: check whether the --upgrade has any impact when the config is a flake). (TODO adapt the command with the parameters to specify another location of the config files if they are not inside `/etc/nix`).

Et voilà!

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

