# Server environment for dedicated inference workloads.
#
# Minimal base: SSH, Tailscale, NixOS base services, no gaming, no kids'
# services, no peripheral daemons. The family user accounts (nicky, aeiuno,
# sven, aaron) and their home-manager software config run here exactly as on
# laptop-p16: server-nike's intended use is inference (daily), with desktop
# use in between, so nicky's inference stack (Strata, Unsloth Studio with
# GPU passthrough, the always-on Orca server) is enabled via the
# commonHm.hostName gates in users/nicky/nicky-hm.nix. The desktop stack
# itself (KDE Plasma, Wayland default) is a host delta in
# hosts/server-nike/server-nike.nix.

{ config, lib, pkgs, ... }:

with lib;
{
  imports = [
    # Base host policy: Nix settings, base packages, locale/timezone.
    ../roles/base.nix
    ../roles/bees.nix
    ../roles/fonts.nix
    ../roles/i18n/fr_BE.nix
    ../roles/nix-gc.nix
    ../roles/shell.nix

    # Infrastructure.
    ../services/openssh.nix
    ../services/tailscale.nix
    ../services/ssh-user-keys.nix
    ../services/syncthing

    # Inference: podman for Unsloth Studio container.
    ../services/podman.nix

    # Binary cache server: distributes built store paths over the LAN.
    ../services/nix-serve.nix
  ];

  # Distribute the family SSH identities + authorized_keys.
  services.sshUserKeys.enable = true;

  # Tailscale firewall: allow SSH + Tailscale internal traffic.
  networking.firewall.allowedUDPPorts = [ 41641 ]; # Tailscale DERP fallback

  # nftables firewall backend: the scoped service rules in the host file's
  # extraInputRules (nix-serve, orca, strata, unsloth-studio) are nftables-only
  # text - with the iptables default backend they are silently inert, which is
  # how the orca/nix-serve rules sat dead. The laptops run the nftables backend
  # via environments/laptop-firewall.nix, and no iptables-based
  # extraCommands remain in the server module set, so it evaluates cleanly.
  networking.nftables.enable = true;

  # Syncthing: run on server-nike for model distribution.
  # The device name is set in hosts/server-nike/server-nike.nix.

  # No desktop by default (server-nike adds KDE Plasma as a host delta), no
  # sonos, no tor.
  # No parental controls, no flatpak, no android — the family user accounts
  # exist for Syncthing ACLs and SSH, just not the kids' service stack.
  # No peripherals, no databases, no security daemons that don't belong on a server.
  services.samba.enable = false;
  services.xrdp.enable = false;
  services.tor.enable = false;
  services.postgresql.enable = false;
  services.avahi.enable = false;
  services.printing.enable = false;
}
