# ananicy-cpp: auto-nice daemon with community rules; the C++ rewrite has lower
# CPU/memory overhead than the original Python ananicy. Applied on every host.
{ pkgs, ... }:

{
  services.ananicy = {
    enable = true;
    package = pkgs.ananicy-cpp;
  };
}
