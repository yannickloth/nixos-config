{ config, lib, pkgs, ... }:

with lib;
{
  # KDE Connect: phone/laptop integration (notifications, file share, remote
  # input, clipboard). Enabling this opens the required firewall ports
  # (1714-1764 TCP/UDP) automatically via the programs.kdeconnect module, so
  # KDE Connect firewall config lives here — not in the laptop-general
  # laptop-firewall.nix.
  programs.kdeconnect.enable = true;
}
