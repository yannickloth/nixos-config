{ config, lib, pkgs, ... }:

with lib;

let
  # agenix-encrypted binary-cache signing key for THIS host (generated with
  # `nix-store --generate-binary-cache-key <host>-cache-1`); the matching
  # public key is trusted in roles/nix.nix. Hosts without a key keep serving
  # unsigned narinfos (and peers ignore their paths).
  cacheKeyFile = ../../secrets/nix-cache-${config.networking.hostName}.key.age;
  hasCacheKey = builtins.pathExists cacheKeyFile;
in
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
    # Sign the narinfos so peers (require-sigs = true, the default) accept the
    # paths; nix-serve loads it as a systemd credential (LoadCredential).
    secretKeyFile = mkIf hasCacheKey "/run/agenix/nix-cache-key";
    # Defence in depth: the nftables rule in environments/laptop-firewall.nix
    # restricts :5000 to the tailnet, but the service itself should not accept
    # anything else either (an unrelated firewall change must not expose the
    # whole store).
    serviceConfig.IPAddressAllow = [ "127.0.0.1/32" "::1/128" "100.64.0.0/10" "fd7a:115c:a1e0::/48" ];
  };

  age.secrets.nix-cache-key = mkIf hasCacheKey {
    file = cacheKeyFile;
    path = "/run/agenix/nix-cache-key";
    mode = "0400";
    owner = "root";
    group = "root";
  };
}
