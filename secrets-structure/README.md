# `secrets/` — what lives here (and why it's never committed)

This directory mirrors the layout of the **gitignored** `secrets/` folder at the
repo root. The real secret files must **never** be committed; this tree exists
only to document the expected structure so that a fresh checkout shows what goes
where. The actual data lives in `secrets/`, which git ignores via `.gitignore`
(`secrets/**`).

## Purpose

`secrets/syncthing/<host>/` holds the **Syncthing node identity** for each host:
the device `cert.pem` and private `key.pem`. Together they authenticate that
host to every peer and grant full read access to every synced folder, so they
are secret. The corresponding public **device IDs** are committed in
`services/syncthing/pool.nix`.

## Expected layout

```
secrets/
└── syncthing/
    ├── laptop-p16/     cert.pem, key.pem   # device VCAGGHS-…
    ├── laptop-hera/    cert.pem, key.pem   # device 6RRKHEE-…
    └── laptop-xps/     cert.pem, key.pem   # device MMPI6MM-…
```

- Each subdirectory holds exactly two files: `cert.pem` and `key.pem`.
- The `cert.pem`/`key.pem` device ID must match the `id` committed for that
  host in `services/syncthing/pool.nix`.
- The directory name must be the host's `services.syncthing.self` value.

## How these files are used

At activation, `services/syncthing/default.nix` copies the identity from
`secrets/syncthing/<host>/` into `/etc/nixos/secrets/syncthing/<host>/`, which
is where the Syncthing service reads it. If the files are absent, the activation
script falls back to preserving an existing `/var/lib/syncthing` cert, then to
generating a fresh identity (which changes the device ID — see
`users/readmes/parents.md`, "Setting up Syncthing on a new host").

## Rules

- **Never commit** `cert.pem` or `key.pem` (or any copy of them).
- Back them up in **KeePass** so a wiped disk can be re-seeded without changing
  the device ID.
- `secrets/syncthing.zip` (if present) is an archive of the above — also keep it
  out of git.
