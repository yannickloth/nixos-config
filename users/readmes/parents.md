# README — family admin account

This file is installed by the NixOS config and is **root-owned, read-only and
immutable** — you cannot edit or delete it. The same content is placed in each
parent's home (`nicky`, `aeiuno`) on every family host. Source of truth:
`users/readmes/parents.md` in the flake, applied with:

    sudo nixos-rebuild switch --flake ~/code/nixos-config

## Host

- This is one of the family laptops, running NixOS from the flake at
  `~/code/nixos-config` (see AGENTS.md in that repo). The same base config is
  applied to every host; details such as hostname, RAM, disk layout and enabled
  services vary per machine.

## Your account

- Admin (sudo/wheel) — you can install software and change the system
- Key groups: `wheel`, `steam` (shared game library), `secrets` (may edit
  /etc/secrets where AI chat is enabled), `kvm`/`libvirtd` (VMs), `podman`,
  `networkmanager`, `lp`/`scanner`, `yubikey`, `tss`, `gamemode`, `syncthing`,
  `filedrop`, `cfo`
- Home-manager config: `users/<your-name>/`

## System highlights

- btrfs + LUKS full-disk encryption; the shared Steam library lives at
  `/steamlib` (see `games/steam.nix`)
- Family AI chat (Open WebUI, where enabled) — see `/etc/secrets/README.md`
  and `services/ai-chat/`
- Secrets (where AI chat is enabled): /etc/secrets (group `secrets`), never in
  git
- Family-safe DNS (malware + adult-content filtering) where configured

## Services & where things live

- **AI chat (Open WebUI):** http://localhost:8080 — the first account that
  signs in becomes the admin, so **sign in as a parent first**, then create the
  kids' accounts (Admin Settings → Users). No password is stored in the config;
  each account's password is chosen on first login.
- **Syncthing:** web UI at http://this-host:8384, synced data lives in `/sync`,
  config in `/var/lib/syncthing` (group `syncthing`).
- **Steam:** shared game installs live in `/steamlib/SteamLibrary/steamapps/common`.
- **Parental controls (malcontent):** manages which **flatpak** apps the kids
  may run (allowlist) and their session time limits. The kids' office/creative/
  media/mail apps (LibreOffice, GIMP, Krita, VLC, Geary) are installed as
  flatpaks precisely so this allowlist can gate them — grant/revoke via the
  parental-controls settings app, **no rebuild needed** (the flatpak installs
  themselves land on the next boot). Firefox stays a native
  package because it carries its own kid policies
  (`users/kid-firefox-policies.nix`). Edit `services/malcontent.nix` for the
  allowlist or schedule.
- **Screen-time enforcement:** sven/aaron get a must-click dialog at 30/15/5
  minutes before the daily lock, then the session is **forced to log out** at
  22:00; malcontent blocks re-login until the next window. Their screens also
  auto-lock after 10 min on AC / 5 min on battery
  (`services/session-limit-reminder.sh`, `services/malcontent.nix`).
- **Grants:** the kids can ask you to allow an app, or to install new software.
  For flatpak apps, grant/revoke through the parental-controls allowlist (no
  rebuild); for native software, edit the config and rebuild with
  `sudo nixos-rebuild switch --flake ~/code/nixos-config`.

## Shared storage & family permissions

- **`/steamlib`** — shared Steam library (`games/steam.nix`). The `steam`
  group (nicky, aeiuno) has read-write access; sven and aaron have read-only
  access (they can launch the games, but cannot modify, delete or update
  them). Install and update games from a parent account.
- **`/sync`** — Syncthing data (`services/syncthing.nix`). The `syncthing`
  group (nicky, aeiuno) has full access; sven and aaron have **no access** by
  default, so shared data can't be wiped. Later we can whitelist a folder for
  them with a `kids`-group ACL in `services/syncthing.nix`.
- **`/filedrop`** — family drop folder (`users/filedrop.nix`). Every family
  account (nicky, aeiuno, sven, aaron) can read, write and delete anything in
  it (no sticky bit — anyone may delete). Each home has a `~/filedrop`
  shortcut, and the folder is exposed over the network as the `filedrop`
  Samba share (`services/samba.nix`, no guest access). Drop a file there to
  pass it to anyone in the family.

## Kid accounts (aaron, sven)

- Parental controls via malcontent: login window 06:00–22:00, flatpak
  allowlist, OARS content-rating filter (no sexual / narcotics / gambling)
- Kid-safe DNS applies machine-wide where configured
- AI chat (where enabled) is available to them with the auto-seeded kid-safety
  gate (`services/ai-chat/filters/kid-safety.py`)
- Shared Steam library: read-only (they play, parents manage); `/sync` is
  blocked for them; shared files pass through `/filedrop`
- Disk quotas: each kid is capped at 50 GiB on `/home`
  (`services/home-quota.nix`)
- Nightly read-only btrfs snapshots of `/home` into `/.snapshots/home` (14 kept)
  for rollback (`services/snapshots.nix`; snapshots only run where `/home` is
  its own subvolume)
- Game binaries are AppArmor-confined: offline-only, write restricted to their
  own home (`security/apparmor.nix`)
- Their UIDs are blocked from the local Tor SOCKS/control ports (9050/9051/9150)
  so they can't bypass the family DNS filter (`services/tor.nix`)
- Email: Geary (gated flatpak) is available; sven uses it with his Gmail
  account (first sign-in is interactive)
