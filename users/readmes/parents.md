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
  `cfo`
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
- **Parental controls (malcontent):** this is the tool that manages which
  **flatpak** apps the kids may run (allowlist) and their session time limits.
  Edit `services/malcontent.nix` to change the allowlist or schedule; on the
  desktop, parental-controls settings apps can manage the per-user allowlist.
- **Screen-time reminders:** sven/aaron get a must-click dialog at 30/15/5
  minutes before the daily lock (`services/session-limit-reminder.sh`).
- **Grants:** the kids can ask you to allow an app, or to install new software;
  you grant it by editing the config (or the parental-controls allowlist) and
  rebuilding with `sudo nixos-rebuild switch --flake ~/code/nixos-config`.

## Kid accounts (aaron, sven)

- Parental controls via malcontent: login window 06:00–22:00, flatpak
  allowlist, OARS content-rating filter (no sexual / narcotics / gambling)
- Kid-safe DNS applies machine-wide where configured
- AI chat (where enabled) is available to them with the auto-seeded kid-safety
  gate (`services/ai-chat/filters/kid-safety.py`)
- Their games + shared Steam library via the `steam` group
