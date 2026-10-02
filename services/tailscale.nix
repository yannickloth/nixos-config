# Tailscale: the private mesh overlay used for cross-host services (nix-serve
# substituters, Syncthing replication, rclone to nestor). Enabled on every host;
# exit-node / advertise-routes options belong per-host when needed.
{ ... }:

{
  services.tailscale.enable = true;
}
