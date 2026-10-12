# Immich (https://immich.app) — self-hosted photo and video backup with local
# AI: CLIP smart search, face detection and duplicate detection.
#
# One module runs the whole stack: the Immich server, its PostgreSQL (with the
# pgvector/vectorchord extensions) and Redis, and immich-machine-learning, all
# under the system-immich.slice. `services.immich.machine-learning.enable`
# defaults to true in the nixpkgs module, so enabling `services.immich` is
# enough for the AI features — no separate service to add.
#
# Enabled on laptop-p16 only (the host with the RTX A3000; see
# hosts/laptop-p16/laptop-p16.nix). NOTE: that import is currently commented
# out because p16 runs CachyOS, not NixOS — this module only takes effect on a
# future NixOS install. On CachyOS the server runs via home-manager
# (packages/immich/home.nix, enabled for nicky in users/nicky/nicky-hm.nix).
# Nicky and aeiuno reach it from their laptops through the web UI —
# installable as a PWA in Chromium — at http://<host>:2283.
#
# Choices:
# - host = "0.0.0.0": the nixpkgs default is "localhost", which binds loopback
#   only and would make openFirewall pointless for remote clients.
# - openFirewall = true: opens TCP 2283 on every interface, i.e. both the LAN
#   and the Tailscale overlay, as requested. Immich still enforces its own
#   user login on top.
# - machine learning stays on CPU: the nixpkgs package is not CUDA-enabled, and
#   CPU inference is the simple default. GPU ML would mean overriding the
#   package with cudaSupport (and passing accelerationDevices), which is
#   deliberately out of scope here.
# - settings is left null, so the instance is configured in the web UI (admin
#   wizard) rather than declaratively.
{ ... }:

{
  services.immich = {
    enable = true;
    host = "0.0.0.0";
    openFirewall = true;
  };
}
