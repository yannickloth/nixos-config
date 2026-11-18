# Server environment for dedicated inference workloads.
#
# Minimal base: SSH, Tailscale, NixOS base services, no desktop, no gaming,
# no kids, no peripheral daemons. Strata and Unsloth Studio are wired in
# users/nicky.nix (they check `commonHm.hostName`), so no per-host plumbing
# is needed beyond the shared NM/SSH/Tailscale stack.

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
  ];

  # Distribute the family SSH identities + authorized_keys.
  services.sshUserKeys.enable = true;

  # Tailscale firewall: allow SSH + Tailscale internal traffic.
  networking.firewall.allowedUDPPorts = [ 41641 ]; # Tailscale DERP fallback

  # Syncthing: run on server-nike for model distribution.
  # The device name is set in hosts/server-nike/server-nike.nix.

  # No desktop, no xrdp, no avahi, no printing, no sonos, no tor.
  # No kids, no parental controls, no gaming, no flatpak, no android.
  # No peripherals, no databases, no security daemons that don't belong on a server.
  services.avahi.enable = false;
  services.printing.enable = false;
  services.samba.enable = false;
  services.scanning.enable = false;
  services.sonos.enable = false;
  services.xrdp.enable = false;
  services.tor.enable = false;
  services.postgresql.enable = false;
  services.clamav.enable = false;
  security.malcontent.enable = false;
  hardware.printers.enable = false;
}
