# Hyprland (Omarchy-style Wayland session)

An Omarchy-inspired Wayland session, offered **alongside** Plasma (Plasma stays
the default). The compositor/session is registered system-wide; the per-user
configuration is managed by home-manager.

## Where it lives

| Path | Role |
| --- | --- |
| `desktop/hyprland.nix` | NixOS: enables `programs.hyprland`, portals, udisks2/gvfs, polkit/KWallet PAM, baseline tools. Imported by `environments/family-laptop.nix` (all laptops). |
| `users/hyprland.nix` | Home-manager: the Omarchy-style Hyprland config, Quickshell bar, helpers, theming. |
| `users/quickshell/omarchy/` | Quickshell shell: `shell.qml` (bar) + `QuickPanel.qml` (quick settings). |

## Profiles

Two options on the home-manager module:

- `hyprland.enable = true` — a sane, working Hyprland (bar, keybinds, media
  keys, screen blank + lock, polkit agent, screenshots, screen recording).
- `hyprland.omarchy = true` — the full Omarchy-style experience: Walker
  launcher, mako notifications + DND, hyprpaper wallpaper, gammastep night
  light, cliphist, udiskie automount, NetworkManager/Bluetooth applets, KWallet
  autostart, matugen theming, nwg-displays, OCR/emoji/calculator.

Adults (`nicky`, `aeiuno`) set both; kids (`sven`, `aaron`) get `enable` only.

## Keybindings

`SUPER` (`$mod`), mirroring Omarchy's defaults.

| Keys | Action |
| --- | --- |
| `SUPER` `Return` | Terminal (alacritty) |
| `SUPER` `Q` / `W` | Close window |
| `SUPER` `F` (`CTRL` for tiled) | Fullscreen |
| `SUPER` `T` / `P` / `J` | Float / pseudo / toggle split |
| `SUPER` arrows | Move focus |
| `SUPER SHIFT` arrows | Swap window |
| `SUPER CTRL`/`ALT` arrows | Resize |
| `SUPER` `1`–`0` | Workspace 1–10 |
| `SUPER SHIFT` `1`–`0` | Move window to workspace |
| `SUPER` `TAB` / `SHIFT TAB` | Next / previous workspace |
| `SUPER` `S` | Scratchpad |
| `SUPER` `` ` `` | Overview (Hyprspace; NixOS only) |
| `SUPER` `K` | Keybindings cheatsheet (fuzzel) |
| `SUPER` `Space` | Launcher (walker) |
| `SUPER` `PRINT` / `SHIFT PRINT` / `PRINT` | Colour picker / region+annotate / full screenshot |
| `SUPER ALT` `PRINT` | Toggle screen recording (wf-recorder) |
| `SUPER CTRL` `PRINT` | OCR a region to clipboard |
| `SUPER CTRL` `V` | Clipboard history |
| `SUPER CTRL` `L` | Lock (hyprlock) |
| `SUPER CTRL` `N` | Toggle night light |
| `SUPER CTRL` `D` | Display arrangement (nwg-displays) |
| `SUPER CTRL` `E` / `Q` | Emoji picker / calculator |
| `XF86` audio/brightness | Volume (swayosd OSD) / brightness |

## Theming (matugen)

`home.activation.omarchyTheme` runs `omarchy-theme` on the first switch (it is
skipped once `colors.json` exists, so a user's own re-theme survives later
switches). It derives a palette from the wallpaper (defaults to a bundled
gradient) with matugen and writes:

- `~/.config/omarchy/colors.json` — read by the Quickshell bar.
- `~/.config/omarchy/hypr-colors.lua` — a Lua table (`{ accent, inactive }`)
  loaded by `hyprland.lua` (with a `pcall`/Catppuccin fallback) for the border
  colours.

Re-theme with any image: `omarchy-theme /path/to/wallpaper.jpg`. If matugen or
jq yields nothing, a Catppuccin fallback is written, so the desktop is never
left unstyled.

## Night light

`gammastep` runs as a user service (`~/.config/systemd/user`) with the
household's location (Luxembourg), shifting the colour temperature at sunset.
`SUPER CTRL N` (or the quick-panel toggle) sends `SIGUSR1` to toggle it.

## Secret Service

KWallet (the same service KDE uses) provides `org.freedesktop.secrets`.
`kwalletd6` is autostarted in the session and unlocked at SDDM login via
`security.pam.services.sddm.kwallet.enable`. VS Code, Chromium,
`git-credential-libsecret`, etc. work without extra prompts.

## CachyOS prerequisites

On CachyOS the NixOS module does nothing. Home-manager only writes the per-user
config (`users/hyprland.nix` sets `package = null` and `portalPackage = null`
there), so **both the compositor binary and the SDDM session entry come from
pacman**:

```sh
sudo pacman -S hyprland xdg-desktop-portal-hyprland xdg-desktop-portal-gtk
sudo systemctl restart sddm
```

`hyprland` also provides the session entry and pulls `xorg-xwayland`; the
portal is a separate package (`xdg-desktop-portal-hyprland`). Install `uwsm` if
you want the extra `hyprland-uwsm.desktop` (systemd-managed) session entry.
The keybindings cheatsheet, `hypridle` and `omarchy-theme` call `hyprctl` from
`PATH` on CachyOS so they always talk to the running (pacman) compositor.

`ls /usr/share/wayland-sessions/` should then list `hyprland.desktop`, and SDDM
will offer it. The Hyprspace overview is disabled on CachyOS (the nixpkgs-built
plugin cannot load into the pacman Hyprland).

### SDDM Wayland greeter vs. Hyprland

The CachyOS SDDM Wayland greeter (`/usr/lib/sddm/sddm.conf.d/zz-wayland.conf`,
a `kwin_wayland --drm` greeter) leaves `WAYLAND_DISPLAY` in the session
environment. Plasma avoids problems because `startplasma-wayland` unsets it, but
`start-hyprland` does not, and aquamarine **deliberately** uses its nested
Wayland backend whenever `WAYLAND_DISPLAY` is set — so the session ends up
nested inside the greeter (black screen, output `WAYLAND-1` 0×0) instead of
taking DRM.

`users/common-hm.nix` clears it for CachyOS in `programs.zsh.profileExtra`
(`unset WAYLAND_DISPLAY`); SDDM starts the session via `$SHELL --login`, which
sources `~/.zprofile`. The X11-greeter alternative (`DisplayServer=x11` in
`/etc/sddm.conf.d/`) avoids the leak entirely if you prefer not to rely on the
login profile.

## Applying

```sh
# CachyOS (home-manager only)
home-manager switch --flake ~/code/nixos-config/users#nicky

# NixOS hosts
sudo nixos-rebuild switch --flake ~/code/nixos-config
```
