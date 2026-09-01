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
- Family AI chat (Open WebUI, on every host) — see `/etc/secrets/README.md`
  and `services/ai-chat/`
- Secrets: /etc/secrets (group `secrets`), never in
  git
- Family-safe DNS (malware + adult-content filtering) where configured
- Kernel hardening via sysctls on the (CachyOS) kernel: dmesg/pointer/BPF
  restrictions (`roles/base.nix`); the system journal is persistent, so kids'
  sessions can be reviewed across reboots (`journalctl`).

## Services & where things live

- **AI chat (Open WebUI):** http://localhost:8080 — the first account that
  signs in becomes the admin, so **sign in as a parent first**, then create the
  kids' accounts (Admin Settings → Users). No password is stored in the config;
  each account's password is chosen on first login.
- **Syncthing:** web UI at http://this-host:8384, synced data lives in `/sync`,
  config in `/var/lib/syncthing` (group `syncthing`). Login is the shared
  account user `nicky` + the password in `/etc/secrets/syncthing-gui-password`
  (Syncthing has a single GUI account for nicky + aeiuno).

### Setting up Syncthing on a new host

Syncthing runs as a single system service on every host and is configured
declaratively from `services/syncthing/`. All 34 folders replicate to nestor
and the other laptops as the closest-to-backup copy. Follow these steps once
per host.

1. **Wire the host into the config** (`hosts/<host>/<host>.nix`):
   - Add `../../services/syncthing` to the `imports` list (all hosts already do).
   - Set `services.syncthing.self = "<device-name>";` where `<device-name>` is a
     key of the device map in `services/syncthing/pool.nix` (e.g. `laptop-p16`,
     `laptop-hera`, `laptop-xps`). The module derives that host's folders and
     peers from the pool automatically.
2. **Make sure the device has a stable identity (cert/key).** The device ID is
   the public hash of its cert; the cert/key are the private secret. On the
   host, the cert/key live in `/etc/nixos/secrets/syncthing/<device-name>/`.
   The activation script provisions them on first activation, in this priority:
   1. A cert/key already present at `/etc/nixos/secrets/syncthing/<device-name>/`
      (e.g. restored from KeePass) → kept, ID stable.
   2. A pre-generated copy in the repo at `secrets/syncthing/<device-name>/`
      (gitignored) → copied in. Used for pre-seeded hosts like laptop-p16 and
      laptop-xps; the private key must never be committed.
   3. An existing `/var/lib/syncthing/{cert,key}.pem` → preserved, so an
      already-registered host keeps its device ID.
   4. Otherwise a fresh identity is generated (new, unseeded host).
   If no cert is seeded and a fresh one is generated, the device ID changes —
   update it in `pool.nix` and on every peer.

   **Existing host (e.g. laptop-hera) keeping its ID:** the activation script
   auto-preserves a cert only if it's at `/var/lib/syncthing/` (where the
   config's `configDir` put it). If syncthing was set up elsewhere (a per-user
   run, or an older config), find its config dir and copy the pair in. On the
   old host, locate the cert via the running service:
   ```
   systemctl show syncthing -p ExecStart   # look for --config=PATH, or
   ps aux | grep syncthing                 # --config=PATH on the command line
   ```
   The cert/key are `<PATH>/cert.pem` and `<PATH>/key.pem` (per-user runs use
   `~/.config/syncthing/` or `~/.local/state/syncthing/`). Copy them into the
   gitignored repo dir `secrets/syncthing/<device-name>/` (or directly to
   `/etc/nixos/secrets/syncthing/<device-name>/`), and confirm the device ID
   matches the one in `pool.nix`:
   ```
   sudo syncthing device-id <PATH>/cert.pem
   ```
3. **Set the GUI password.** Create `/etc/secrets/syncthing-gui-password`
   (plaintext, one shared credential for nicky + aeiuno; the GUI user is
   `nicky`):
   ```
   sudo sh -c 'umask 077; printf "%s\n" "<a strong shared password>" > /etc/secrets/syncthing-gui-password'
   ```
4. **Apply the config:** `sudo nixos-rebuild switch --flake ~/code/nixos-config`.
   On first run `overrideFolders/overrideDevices` reconcile the declared set —
   folders/devices not in the pool are removed, so the exact 34 folders appear.
5. **Verify:** open http://this-host:8384, log in, and confirm the folder list
   matches the 34 declared folders and that all peers show up. Data lands under
   `/sync/<folder>`; each user's `~/sync` symlink points there. Watch the first
   sync complete before relying on a host as backup.
6. **Back up the device secret** (the private key + cert) into KeePass so a
   wiped disk can be re-seeded without changing the device ID. The device ID
   itself is public and already in `pool.nix`.
- **Steam:** shared game installs live in `/steamlib/SteamLibrary/steamapps/common`.
- **Parental controls (malcontent):** manages which **flatpak** apps the kids
  may run (allowlist) and their session time limits. The kids' office/creative/
  media/mail apps (LibreOffice, GIMP, Krita, VLC, Geary) are installed as
  flatpaks precisely so this allowlist can gate them — grant/revoke via the
  parental-controls settings app, **no rebuild needed** (the flatpak installs
  themselves land on the next boot). Firefox stays a native
  package because it carries its own kid policies
  (`users/kid-firefox-policies.nix`). The defaults live in
  `services/malcontent.nix`, but once a kid's account is set up the existing
  permissions are **kept across rebuilds** — a rebuild only seeds the config on
  first setup. To re-apply the Nix defaults, remove the
  `[com.endlessm.ParentalControls.*]` sections from
  `/var/lib/AccountsService/users/<kid>` (or delete that file) and rebuild.
- **Screen-time enforcement:** sven/aaron get a pop-up warning at 30/15/5
  minutes before the daily lock, then the session is **forced to log out** at
  22:00; malcontent blocks re-login until the next window. Their screens also
  auto-lock after 10 min on AC / 5 min on battery
  (`services/session-limit-reminder.sh`, `services/malcontent.nix`).
- **Grants:** the kids can ask you to allow an app, or to install new software.
  For flatpak apps, grant/revoke through the parental-controls allowlist (no
  rebuild); for native software, edit the config and rebuild with
  `sudo nixos-rebuild switch --flake ~/code/nixos-config`.

## Installing apps: flatpak vs nixpkgs

Apps are installed two different ways here, and the choice is driven by the
kids' parental controls:

- **Flatpak — sandboxed and malcontent-gated.** The parental controls only
  filter *flatpak* apps, so anything the kids should be able to run (or that
  you want to allow/block without a rebuild) comes from flatpak: their
  office/creative/media/mail apps (LibreOffice, GIMP, Krita, VLC, Audacious,
  Geary) plus the GNOME/KDE utility apps in the allowlist (dolphin, okular,
  gwenview, kalk, …). Declared in `roles/base.nix` under `apps.flatpak`, kept in sync
  with the allowlist in `services/malcontent.nix`; installs land on the next
  boot. Grant/revoke via the parental-controls settings app — no rebuild.
- **nixpkgs — native, deep system access.** Everything that needs groups/ACLs,
  GPU, gamepads, or its own policies: the games (Steam and Lutris on
  `/steamlib`, and the kids' native games ktuberling, extremetuxracer,
  supertux, luanti, …), Firefox (its kid policies
  `users/kid-firefox-policies.nix` apply to the native build only), and
  CLI/dev tools (python, racket, editors). Changes require a rebuild:
  `sudo nixos-rebuild switch --flake ~/code/nixos-config`.

Flatpak apps are also **sandboxed from the shared folders**: they can't see
`/steamlib`, `/sync` or `/filedrop` unless an override grants them access. The
kids' office/creative apps already get `/filedrop` so they can save into the
drop folder (`apps.flatpak.overrides` in `roles/base.nix`); `/steamlib` and
`/sync` are deliberately native/group-accessed only — they are the protected
shared data.

Rule of thumb: **if malcontent should be able to allow or block it for a kid,
make it a flatpak; if it needs groups/GPU/policies, keep it native.**

## Shared storage & family permissions

- **`/steamlib`** — shared Steam library (`games/steam.nix`). The `steam`
  group (nicky, aeiuno) has read-write access; sven and aaron have read-only
  access (they can launch the games, but cannot modify, delete or update
  them). Install and update games from a parent account.
- **`/sync`** — Syncthing data (`services/syncthing/`). The `syncthing`
  group (nicky, aeiuno) has full access; sven and aaron have **no access** by
  default, so shared data can't be wiped. Later we can whitelist a folder for
  them with a `kids`-group ACL in `services/syncthing/`.
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
- AI chat is available to them with the auto-seeded kid-safety
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
- Firefox is locked down for them (`users/kid-firefox-policies.nix`): DoH is
  pinned to the family filter (family.cloudflare-dns.com), private browsing and
  the "Forget" button are disabled, HTTPS-only is forced, sensitive site
  permissions are blocked by default, no extra search engines, and a read-only
  Gmail bookmark is provided. uBlock Origin is force-installed; all other
  add-ons are blocked.
- They cannot change network/DNS settings or create hotspots (polkit,
  `security/kids.nix`) — so they can't reroute around the family DNS filter;
  connecting to configured networks still works. A build-time assertion also
  guarantees they never get added to `wheel` (no sudo).
- **USB drives:** when a USB stick is plugged in, it is mounted **read-only**
  and scanned with ClamAV automatically (`services/usb-scan.nix`); a desktop
  notification reports the result (clean / threats found). Infected files are
  **reported, never deleted**. For write access to a stick, mount it yourself:
  `sudo mount -o remount,rw <mountpoint>` (kids can't).
