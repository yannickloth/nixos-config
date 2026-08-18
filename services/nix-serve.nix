{ config, lib, pkgs,... }:

with lib;
{
  services.nix-serve={
    enable = true;
    openFirewall = true; # Open ports in the firewall for nix-serve.
    # port = 5000; # Port number where nix-serve will listen on. Default: 5000.
    # bindAddress = "0.0.0.0" # IP address where nix-serve will bind its listening socket.
    # secretKeyFile
  };
}
