# Shared module set for the portable family machines: laptop-hera,
# laptop-p16 and laptop-xps — plus desktop-leto, which imports it too (the
# file keeps its historical name; the desktop is a member of this layer).
#
# family-laptop = family-host + the chassis specifics that must NOT reach
# hosts without them:
#   - environments/laptop.nix: power management (suspend, thermald,
#     power-profiles-daemon, zram, upower) and the nftables firewall
#     (laptop-firewall.nix, nix-serve on Tailscale only). server-nike, an
#     inference server that must never sleep, skips this layer on purpose.
#   - hardware/intel_graphics.nix: VA-API/Vulkan stack for hosts with an
#     Intel iGPU. It mkForces hardware.graphics.extraPackages to the Intel
#     media drivers, so a host without an iGPU (server-nike: RTX 3060 only)
#     must not import it.
#
# Timezone: roles/base.nix defaults to Europe/Luxembourg — no environment
# pins its own, so there is a single source and no mkForce conflict.
#
# Host-specific modules (kernel choice, per-host apps, RAM-dependent settings,
# the home-manager user wiring) stay in hosts/<host>/<host>.nix. Current deltas:
#   laptop-hera:  apps/benchmark.nix
#   laptop-p16:   apps/benchmark.nix, apps/obs-studio.nix, apps/wine.nix
#   laptop-xps:   apps/noson.nix, apps/wine.nix, desktop/plasma.nix
#   desktop-leto: desktop/plasma.nix, apps/wine.nix, plus its own GPU/Wi-Fi
#                 hardening
{ lib, ... }:

{
  imports = [
    ./family-host.nix

    # Laptop environment (power management, zram, thermald, timezone) and its
    # firewall (nftables + nix-serve Tailscale rule).
    ./laptop.nix

    # Intel iGPU graphics stack (see the header: iGPU hosts only).
    ../hardware/intel_graphics.nix
  ];
}
