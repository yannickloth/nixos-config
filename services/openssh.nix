# provides openssh defaults
{ lib, ... }:

with lib;

{
  config = {
    # Enable OpenSSH. openFirewall defaults to true, so port 22 is opened by
    # the module itself (no explicit firewall entry needed).
    services.openssh.enable = mkDefault true;

    # root now has a break-glass password (users/passwords.nix). Disable root
    # SSH login entirely (not just password auth — "prohibit-password", the
    # nixpkgs default, still allows root key login). Interactive root access is
    # via `sudo` from a wheel account.
    services.openssh.settings = {
      PermitRootLogin = mkDefault "no";
      # Password auth stays enabled (the default). NOTE: the stated reason no
      # longer holds - services/sshUserKeys.nix installs the family identities
      # on all four hosts, so key login works everywhere. Kept as-is because
      # disabling password auth is a separate decision (recovery access,
      # non-NixOS peers); flip PasswordAuthentication to false here when that is
      # settled.
    };
  };
}
