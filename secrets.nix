# agenix recipient configuration.
#
# This file is used by the `agenix` CLI to know which public SSH keys to encrypt
# each secret to. It is NOT imported into the NixOS/home-manager config; the
# actual secret *mounting* is declared per-module via `age.secrets`.
#
# Recipients are SSH public keys (age accepts `ssh-ed25519` keys directly, no
# conversion needed). The matching private keys live in the gitignored
# `ssh-keys/` directory on this machine and are distributed to each host/user
# (backed up in KeePassXC). See secrets-structure/README.md.
#
# STRATEGY: per-secret recipient sets — there is no global "all" union. Each
# secret is encrypted only to the keys that must decrypt it:
#   - host-wide system secrets (syncthing GUI password, Open WebUI keys, login
#     password hashes) -> `hosts` (every host key)
#   - a host's Syncthing device identity -> that host's key only
#   - nicky's personal API keys -> `user-nicky` + `hosts` (for recovery)
# So a kid's (or another user's) key cannot read a secret it has no business
# reading. See secrets-structure/README.md.

let
  # --- Recipients: SSH public keys -----------------------------------------
  # Generated in ssh-keys/ (gitignored), `ssh-keygen` host/user keys.

  host-laptop-p16 = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIK4TZqDcPPeDcBpqpHKdD22h60uxF0PoV1gelJ7qbC01";
  host-laptop-hera = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDHpBH6eidO8g+n4rqo9pVEsYX425CsDBloRbQoci0gD";
  host-laptop-xps = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAQkJFvXdkXG8Q9Chq7DFDIe71T2M2EaEvbdEi7Dg4an";
  host-laptop-travelmate = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGDwgXXr+XgOfH/vtOCcyXZwZTg7r5iVAvIf3IHs7Ii1";

  user-nicky = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIL7qyn3G5ztyNoQ6u4RZ1nJZaDNHcQRGhKaVj0i8pC8m";

  # All host keys. Host-wide system secrets and the login password hashes are
  # encrypted to this set.
  hosts = [
    host-laptop-p16
    host-laptop-hera
    host-laptop-xps
    host-laptop-travelmate
  ];
in
{
  # --- System secrets ------------------------------------------------------
  # Decrypted on NixOS hosts via age.identityPaths (their SSH host keys).
  # Scoped to `hosts`: services only ever decrypt these as root on a host, so a
  # user key must not be able to read them.

  # Syncthing web-UI password, shared across all hosts.
  "syncthing-gui-password.age".publicKeys = hosts;

  # Family AI-chat provider keys (Open WebUI).
  "open-webui.env.age".publicKeys = hosts;

  # Per-host Syncthing device identity (cert.pem + key.pem). Encrypted to the
  # OWNING host only: the device key belongs to that host, so no other host or
  # user key can impersonate it. The device ID is preserved on reinstall by
  # restoring that host's private key from KeePassXC (see secrets-structure).
  "syncthing/laptop-hera/cert.pem.age".publicKeys = [ host-laptop-hera ];
  "syncthing/laptop-hera/key.pem.age".publicKeys = [ host-laptop-hera ];
  "syncthing/laptop-p16/cert.pem.age".publicKeys = [ host-laptop-p16 ];
  "syncthing/laptop-p16/key.pem.age".publicKeys = [ host-laptop-p16 ];
  "syncthing/laptop-xps/cert.pem.age".publicKeys = [ host-laptop-xps ];
  "syncthing/laptop-xps/key.pem.age".publicKeys = [ host-laptop-xps ];
  # Prepared identity for the (not-yet-configured) laptop-travelmate host.
  "syncthing/laptop-travelmate/cert.pem.age".publicKeys = [ host-laptop-travelmate ];
  "syncthing/laptop-travelmate/key.pem.age".publicKeys = [ host-laptop-travelmate ];

  # --- User secrets --------------------------------------------------------
  # Decrypted via the home-manager agenix module with the user's key.

  # nicky's AI-chat API keys (env-file format, KEY=VALUE lines). Scoped to
  # nicky's own key + the host keys (recovery); NOT to the other users' keys.
  "nicky.nix.age".publicKeys = [ user-nicky ] ++ hosts;

  # Per-user password hashes (SHA-512 crypt), consumed by users/passwords.nix
  # as users.users.<n>.hashedPasswordFile. Encrypted to host keys only.
  "passwords/nicky.hash.age".publicKeys = hosts;
  "passwords/aeiuno.hash.age".publicKeys = hosts;
  "passwords/sven.hash.age".publicKeys = hosts;
  "passwords/aaron.hash.age".publicKeys = hosts;

  # root break-glass password (see users/passwords.nix). Same host-key scope.
  "passwords/root.hash.age".publicKeys = hosts;

  # CIFS client credentials for the nestor mount. NOTE: services/cifs-nestor.nix
  # is not currently imported by any host; add its .age file here once wired up.
  # "cifs/nestor.secrets.age".publicKeys = hosts;
}
