{ config, lib, pkgs,... }:

with lib;
{
  services.nix-serve = {
    enable = true;
    # Distributed builds across the three laptops over Tailscale: each host
    # serves its store and pulls from the others (see the substituter lines in
    # roles/nix.nix). Must listen on all interfaces (0.0.0.0) — firewall access
    # to port 5000 is restricted to the Tailscale CGNAT subnet in
    # environments/laptop-firewall.nix.
    bindAddress = "0.0.0.0";
    openFirewall = false; # handled via the nftables rule, not openFirewall
    # port = 5000; # Port number where nix-serve will listen on. Default: 5000.
    # secretKeyFile
  };
}
