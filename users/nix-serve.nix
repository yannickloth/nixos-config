# nix-serve for the standalone CachyOS deployment (laptop-p16).
#
# NixOS hosts get the peer cache from services/nix-serve.nix (system unit,
# agenix signing key). laptop-p16 currently runs CachyOS, where no NixOS
# module runs, so the same cache is exposed here as a user service for nicky
# only — the same always-on pattern as the orca runtime server on p16 (whose
# activation also enables lingering, so this unit keeps running after logout).
#
# Peers already list http://laptop-p16.bee-blues.ts.net:5000/ as a substituter
# and trust laptop-p16-cache-1 (roles/nix.nix), so only the server is missing
# on the CachyOS install.
#
# Signing key: secrets/nix-cache-laptop-p16.key.age is encrypted to the
# host-laptop-p16 key (the NixOS agenix path) AND user-nicky, so the
# home-manager agenix module (see `age.secrets` below) decrypts it to a
# user-local path on every switch — no manual key setup on CachyOS. Without
# the key the service still runs, serving unsigned narinfos that peers
# (require-sigs, the default) ignore — the same degradation as the NixOS
# module.
{ config, pkgs, lib, ... }:

let
  # Only the standalone p16 deployment, and only nicky: the other p16 users
  # must not start a second instance, and a future NixOS p16 install
  # (isCachyOS false) keeps the system unit as the cache owner.
  enabled = config.commonHm.hostName == "laptop-p16"
    && config.commonHm.isCachyOS
    && config.home.username == "nicky";
  keyPath = config.age.secrets."nix-cache-laptop-p16.key".path;
  start = pkgs.writeShellScriptBin "nix-serve-start" ''
    key="${keyPath}"
    if [ -s "$key" ]; then
      # nix-serve signs every narinfo when this points at a cache signing key.
      export NIX_SECRET_KEY_FILE="$key"
    fi
    # Port 5000 matches the substituter URL in roles/nix.nix; the store is
    # served read-only.
    exec "${pkgs.nix-serve}/bin/nix-serve" --listen 0.0.0.0:5000
  '';
in
{
  config = lib.mkIf enabled {
    # Decrypt the cache signing key with nicky's user agenix identity
    # (~/.ssh/agenix_nicky, distributed by services/ssh-user-keys.nix — the
    # same mechanism the opencode provider keys use on this host).
    age.secrets."nix-cache-laptop-p16.key" = {
      file = ../secrets/nix-cache-laptop-p16.key.age;
      mode = "0400";
    };

    systemd.user.services.nix-serve = {
      Unit = {
        Description = "Nix binary cache for Tailscale peers (nix-serve)";
        # The signing key is materialized by the agenix user oneshot (agenix
        # home-manager module, same default.target) and nix-serve reads it once
        # at startup; without this ordering a boot race would run it unsigned
        # until the next restart.
        After = [ "agenix.service" ];
      };
      Install = {
        WantedBy = [ "default.target" ];
      };
      Service = {
        ExecStart = "${start}/bin/nix-serve-start";
        # Same source gate as the NixOS unit (services/nix-serve.nix):
        # loopback and the Tailscale CGNAT only, enforced at the socket level
        # regardless of any host firewall.
        IPAddressAllow = [
          "127.0.0.1/32"
          "::1/128"
          "100.64.0.0/10"
          "fd7a:115c:a1e0::/48"
        ];
        Restart = "always";
        RestartSec = "5s";
      };
    };
  };
}
