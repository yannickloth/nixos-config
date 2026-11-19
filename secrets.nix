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
#   - host-wide system secrets (syncthing GUI password, opencode provider keys,
#     login password hashes, the family SSH identities, the PostgreSQL role
#     password) -> `hosts` (every host key)
#   - a host's Syncthing device identity -> that host's key only
#   - nicky's personal API keys -> `user-nicky` + `hosts` (for recovery)
#   - the PostgreSQL role password -> `hosts` + `user-nicky` + `user-aeiuno`.
#     It is consumed twice: by the system unit (host key) and by nicky's
#     home-manager ~/.pgpass wiring (user key). user-aeiuno is not required by
#     any consumer today and could be dropped, but is kept so the file matches
#     the scope the opencode keys use.
# So a kid's (or another user's) key cannot read a secret it has no business
# reading. See secrets-structure/README.md.
#
# `hosts` currently lists host-laptop-travelmate, which has no
# nixosConfigurations entry (a spare identity kept for a future install).
# That is harmless — an unused recipient only means the file can also be
# decrypted with a key nobody deploys — but it is not a configured host.

let
  # --- Recipients: SSH public keys -----------------------------------------
  # Generated in ssh-keys/ (gitignored), `ssh-keygen` host/user keys.

  host-laptop-p16 = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIK4TZqDcPPeDcBpqpHKdD22h60uxF0PoV1gelJ7qbC01";
  host-laptop-hera = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDHpBH6eidO8g+n4rqo9pVEsYX425CsDBloRbQoci0gD";
  host-laptop-xps = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAQkJFvXdkXG8Q9Chq7DFDIe71T2M2EaEvbdEi7Dg4an";
  host-laptop-travelmate = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGDwgXXr+XgOfH/vtOCcyXZwZTg7r5iVAvIf3IHs7Ii1";
  host-desktop-leto = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHGcaJSty1Sies8J42+xvPDHEDDVy1wTgBDLnV5JdvSg";
  host-server-nike = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDHJ3Mhw7RpHapDKS7iRT8/qBrahEquDMVBAYh1eAW2B";

  user-nicky = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIL7qyn3G5ztyNoQ6u4RZ1nJZaDNHcQRGhKaVj0i8pC8m";
  user-aeiuno = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIASyK+Od8c/gEwvvdtz1Lovd/qnomAeCRr+cPmhn6qvQ";

  # All host keys. Host-wide system secrets and the login password hashes are
  # encrypted to this set.
  hosts = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHGcaJSty1Sies8J42+xvPDHEDDVy1wTgBDLnV5JdvSg"
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDHpBH6eidO8g+n4rqo9pVEsYX425CsDBloRbQoci0gD"
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIK4TZqDcPPeDcBpqpHKdD22h60uxF0PoV1gelJ7qbC01"
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGDwgXXr+XgOfH/vtOCcyXZwZTg7r5iVAvIf3IHs7Ii1"
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAQkJFvXdkXG8Q9Chq7DFDIe71T2M2EaEvbdEi7Dg4an"
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDHJ3Mhw7RpHapDKS7iRT8/qBrahEquDMVBAYh1eAW2B"
  ];
in
{
  # --- System secrets ------------------------------------------------------
  # Decrypted on NixOS hosts via age.identityPaths (their SSH host keys).
  # Scoped to `hosts`: services only ever decrypt these as root on a host, so a
  # user key must not be able to read them.

  # Syncthing web-UI password, shared across all hosts.
  "syncthing-gui-password.age".publicKeys = hosts;

  # Family SSH identities (private halves), distributed by
  # services/ssh-user-keys.nix: agenix decrypts them to /run/agenix on every
  # host and the unit installs them as ~/.ssh/agenix_<user>. Encrypted to
  # `hosts`, because automatic installation needs the host to decrypt them;
  # the matching public keys are committed in users/ssh-public-keys.nix.
  "ssh-user-nicky.key.age".publicKeys = hosts;
  "ssh-user-aeiuno.key.age".publicKeys = hosts;
  "ssh-user-sven.key.age".publicKeys = hosts;
  "ssh-user-aaron.key.age".publicKeys = hosts;

  # Per-host nix-serve binary-cache signing keys. Encrypted to the owning host;
  # the matching public keys are trusted in roles/nix.nix so the peers accept
  # each other's (now signed) store paths. laptop-p16 additionally accepts
  # user-nicky: that host runs CachyOS (no system agenix), and the standalone
  # home-manager deployment decrypts the key with nicky's user identity
  # (users/nix-serve.nix, `age.secrets`).
  "nix-cache-laptop-p16.key.age".publicKeys = [ host-laptop-p16 user-nicky ];
  "nix-cache-laptop-hera.key.age".publicKeys = [ host-laptop-hera ];
  "nix-cache-laptop-xps.key.age".publicKeys = [ host-laptop-xps ];
  "nix-cache-desktop-leto.key.age".publicKeys = [ host-desktop-leto ];

  # Shared LLM provider keys for opencode (OPENAI_API_KEYS JSON). Also readable
  # by user-nicky and user-aeiuno so standalone home-manager on CachyOS (no
  # system agenix, no /etc/secrets) can decrypt it via their user keys
  # (~/.ssh/agenix_<user>); see users/{nicky,aeiuno}/*-hm.nix and
  # users/opencode.nix.
  "opencode-keys.env.age".publicKeys = hosts ++ [ user-nicky user-aeiuno ];

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
  "syncthing/desktop-leto/cert.pem.age".publicKeys = [ host-desktop-leto ];
  "syncthing/desktop-leto/key.pem.age".publicKeys = [ host-desktop-leto ];
  # server-nike identity: pre-generated offline and committed before first
  # boot, so the device ID is known ahead of install. To generate a host
  # identity offline (see parents.md "Setting up Syncthing"):
  #   syncthing generate --home <tmp>        # writes cert.pem + key.pem
  #   syncthing device-id --home <tmp>       # the ID that goes in pool.nix
  #   age -r "ssh-ed25519 <host pub key>" -o secrets/syncthing/<host>/cert.pem.age <tmp>/cert.pem
  #   age -r "ssh-ed25519 <host pub key>" -o secrets/syncthing/<host>/key.pem.age  <tmp>/key.pem
  "syncthing/server-nike/cert.pem.age".publicKeys = [ host-server-nike ];
  "syncthing/server-nike/key.pem.age".publicKeys = [ host-server-nike ];

  # --- User secrets --------------------------------------------------------
  # Decrypted via the home-manager agenix module with the user's key.

  # nicky's personal API keys (env-file format, KEY=VALUE lines). Scoped to
  # nicky's own key + the host keys (recovery); NOT to the other users' keys.
  "nicky.nix.age".publicKeys = [ user-nicky ] ++ hosts;

  # nicky's PostgreSQL role password. Consumed twice: by the system unit
  # (services/postgresql.nix, host key) and by nicky's home-manager .pgpass
  # wiring (user key), so the scope mirrors nicky.nix.age.
  "pg-nicky-password.age".publicKeys = [ user-nicky ] ++ hosts;

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
