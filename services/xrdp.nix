# xRDP — remote desktop for this machine.
#
# Allows concurrent X11 sessions on virtual displays (`:1`, `:2`, …) while the
# physical console stays on its Wayland/KWin session.  Multiple users can
# connect simultaneously; each gets an independent KDE desktop.
#
# SECURITY
#   Port 3389 is restricted to private/Tailscale ranges via
#   `networking.firewall.extraInputRules`.  Access is authenticated with the
#   user's regular Linux password (xRDP's internal PAM auth).
#
#   If you want SSH-tunneled access instead, skip the firewall rule and use:
#     ssh -L 3389:localhost:3389 <user>@<host>
#
{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.services.xrdp;
in
{
  config = mkIf cfg.enable {
    # Safety: xRDP must not run without a firewall — it exposes a full
    # desktop session and is a frequent brute-force target.
    assertions = [
      {
        assertion = config.networking.firewall.enable;
        message = "xRDP requires networking.firewall.enable (port 3389 is a common brute-force target)";
      }
    ];

    # Use our own firewall rules instead of nixpkgs default (which opens to
    # the world).  Port is 3389 by default.
    services.xrdp = {
      openFirewall = false;

      # Launch KDE Plasma for remote sessions instead of xterm.
      defaultWindowManager =
        "${pkgs.kdePackages.plasma-workspace}/bin/startplasma-x11";

      # Enable audio forwarding (PulseAudio module-xrdp) so remote sessions
      # can play sound through the local speakers.
      audio.enable = true;
    };

    # Open port 3389 for xRDP.  Restricted to private + Tailscale networks.
    # 100.64.0.0/10 is the CGNAT range (Tailscale); fd7a:115c:a1e0::/48 is the
    # family's Tailscale IPv6 prefix.
    networking.firewall.extraInputRules = ''
      # xRDP (remote desktop) — private LAN + Tailscale only
      # (one address per line: nftables rejects bare comma-separated
      # saddr lists — use `saddr { a, b }` if you want a set)
      tcp dport 3389 ip saddr 192.168.0.0/16 accept
      tcp dport 3389 ip saddr 10.0.0.0/8 accept
      tcp dport 3389 ip saddr 172.16.0.0/12 accept
      tcp dport 3389 ip saddr 100.64.0.0/10 accept
      tcp dport 3389 ip6 saddr fe80::/10 accept
      tcp dport 3389 ip6 saddr fc00::/7 accept
      tcp dport 3389 ip6 saddr fd7a:115c:a1e0::/48 accept
    '';

    # Restart on failure so remote sessions survive transient X server crashes.
    systemd.services.xrdp.serviceConfig.Restart = "on-failure";
    systemd.services.xrdp-sesman.serviceConfig.Restart = "on-failure";
    systemd.services.xrdp-sesman.serviceConfig.RestartSec = "5";
  };
}
