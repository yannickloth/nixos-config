# Hyprland: an Omarchy-style Wayland session (https://github.com/omacom/omarchy)
# available to every family-laptop user and selectable at the SDDM login screen.
# Plasma stays the default session (see desktop/xserver.nix); this only adds a
# second compositor.
#
# Split of responsibilities:
#   * here (system): install the compositor and register its desktop session
#     entry for all users, wire the Wayland portals, and provide a baseline
#     toolset so the session is usable even before per-user config is applied.
#   * users/hyprland.nix (home-manager): the per-user Omarchy-style config
#     (keybinds, look, Quickshell bar) — a full config for the adults, a
#     lighter one for the kids.
{ pkgs, ... }:

{
  # Registers a sessionPackage with the display manager, so "Hyprland" shows up
  # in SDDM for every user. XWayland is on for the X11 apps in the family stack.
  programs.hyprland = {
    enable = true;
    xwayland.enable = true;
  };

  # File-chooser / screencast portals for Wayland apps. The Hyprland portal and
  # the `configPackages` wiring are added by programs.hyprland itself.
  xdg.portal.extraPortals = [ pkgs.xdg-desktop-portal-gtk ];

  # Storage / filesystem services that Plasma normally pulls in: udisks2 (for
  # udisksctl and udiskie automounting; services/usb-scan.nix also keys its
  # read-only USB policy on it) and gvfs (trash/MTP/network locations in GTK
  # apps). Both are harmless for the Plasma sessions.
  services.udisks2.enable = true;
  services.gvfs.enable = true;

  # hyprlock authenticates through PAM; give it a service of its own so the
  # screen lock can unlock (the default `login` stack is not always reachable).
  security.pam.services.hyprlock = { };

  # Unlock KWallet (the KDE Secret Service) at SDDM login, so apps that read the
  # wallet (VS Code, git-credential-libsecret, …) work in the Hyprland session
  # too. KWallet is used instead of gnome-keyring to match the Plasma setup.
  security.pam.services.sddm.kwallet.enable = true;

  # Baseline Omarchy-style toolset, shared by all users. home-manager adds the
  # same packages per user; duplicates are the same store paths, so this only
  # guarantees the session works even for a user whose config is minimal.
  environment.systemPackages = with pkgs; [
    alacritty
    fuzzel
    walker
    quickshell
    mako
    swayosd
    hyprpicker
    hyprshot
    hypridle
    hyprlock
    hyprpaper
    hyprpolkitagent
    wl-clipboard
    cliphist
    udiskie
    grim
    slurp
    satty
    brightnessctl
    playerctl
    pavucontrol
    networkmanagerapplet
    blueman
  ];
}
