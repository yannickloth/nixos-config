{ config, lib, pkgs,... }:

with lib;
{
  services.nix-serve={
    enable = true;
    openFirewall = false; # Do not expose the binary cache to the network (laptops).
    bindAddress = "127.0.0.1"; # Bind to loopback; only useful for local rebuilds.
    # port = 5000; # Port number where nix-serve will listen on. Default: 5000.
    # secretKeyFile
  };
}
