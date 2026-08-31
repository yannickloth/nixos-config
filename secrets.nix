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
# STRATEGY: union of all recipients. Every secret is encrypted to ALL host keys
# + ALL user keys, so any host/user can decrypt any secret. This is the most
# automatic configuration: no per-host targeting to maintain, one file works
# everywhere. Tradeoff: a compromised key decrypts everything — acceptable
# because the goal is a quick, simple, uniform setup across all hosts.

let
  # --- Recipients: SSH public keys -----------------------------------------
  # Generated in ssh-keys/ (gitignored), `ssh-keygen` host/user keys.

  host-laptop-p16 = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIK4TZqDcPPeDcBpqpHKdD22h60uxF0PoV1gelJ7qbC01";
  host-laptop-hera = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDHpBH6eidO8g+n4rqo9pVEsYX425CsDBloRbQoci0gD";
  host-laptop-xps = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAQkJFvXdkXG8Q9Chq7DFDIe71T2M2EaEvbdEi7Dg4an";
  host-laptop-travelmate = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGDwgXXr+XgOfH/vtOCcyXZwZTg7r5iVAvIf3IHs7Ii1";

  user-nicky = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIL7qyn3G5ztyNoQ6u4RZ1nJZaDNHcQRGhKaVj0i8pC8m";
  user-aeiuno = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIASyK+Od8c/gEwvvdtz1Lovd/qnomAeCRr+cPmhn6qvQ";
  user-sven = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGEsqIouG7nwHEqH0W7r0ywiUtD7em/xKHjKV1PpmFbp";
  user-aaron = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPtH5ncJyvw7qKZ5tQODeNsM0QVvmh9Layw9PJT8JoyN";

  # --- Union of every recipient -------------------------------------------
  # Every secret is encrypted to all of these, so any host or user can decrypt.
  all = [
    host-laptop-p16
    host-laptop-hera
    host-laptop-xps
    host-laptop-travelmate
    user-nicky
    user-aeiuno
    user-sven
    user-aaron
  ];
in
{
  # --- System secrets ------------------------------------------------------
  # Decrypted on NixOS hosts via age.identityPaths (their SSH host keys).

  # Syncthing web-UI password, shared across all hosts.
  "syncthing-gui-password.age".publicKeys = all;

  # Family AI-chat provider keys (Open WebUI).
  "open-webui.env.age".publicKeys = all;

  # Per-host Syncthing device identity (cert.pem + key.pem). Encrypted to the
  # union so a reinstall can decrypt with any restored host/user key; the device
  # ID is preserved by restoring the owning host's private key from KeePassXC.
  "syncthing/laptop-hera/cert.pem.age".publicKeys = all;
  "syncthing/laptop-hera/key.pem.age".publicKeys = all;
  "syncthing/laptop-p16/cert.pem.age".publicKeys = all;
  "syncthing/laptop-p16/key.pem.age".publicKeys = all;
  "syncthing/laptop-xps/cert.pem.age".publicKeys = all;
  "syncthing/laptop-xps/key.pem.age".publicKeys = all;

  # --- User secrets --------------------------------------------------------
  # Decrypted via the home-manager agenix module with the user's key.

  # nicky's AI-chat API keys (env-file format, KEY=VALUE lines).
  "nicky.nix.age".publicKeys = all;

  # CIFS client credentials for the nestor mount. NOTE: services/cifs-nestor.nix
  # is not currently imported by any host; add its .age file here once wired up.
  # "cifs/nestor.secrets.age".publicKeys = all;
}
