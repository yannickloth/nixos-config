# Per-user login passwords, managed declaratively via agenix.
#
# The password *hashes* (SHA-512 crypt) live in `secrets/passwords/<user>.hash.age`,
# encrypted to the host keys only (see secrets.nix) — a user's own key, or
# another user's, must not decrypt a password hash. agenix installs secrets
# before the `users` activation script (`users.deps = [ "agenixInstall" ]` in
# the pinned agenix module), so `hashedPasswordFile` can point straight at the
# decrypted secret.
#
# `users.mutableUsers = false` means accounts are owned by the config: users
# cannot change their own password (a `passwd` change is reverted on the next
# activation). Parents rotate a password by editing the secret and rebuilding:
#
#   mkpasswd -m sha-512
#   sudo agenix -e -i /etc/ssh/ssh_host_ed25519_key secrets/passwords/<user>.hash.age
#   # or re-encrypt everything:  sudo ./scripts/agenix-rekey.sh
#
# A password secret is encrypted to the HOST keys only, so decrypting/re-encrypting
# it needs a host key (root). See secrets-structure/README.md.
{ config, lib, ... }:

let
  # root is included as the local break-glass administrator (console / recovery);
  # wheel users reach root via passwordless sudo. See secrets.nix.
  passwordUsers = [ "nicky" "aeiuno" "sven" "aaron" "root" ];
in
{
  users.mutableUsers = false;

  age.secrets = lib.listToAttrs (map
    (name: {
      name = "password-${name}";
      value = {
        file = ../secrets/passwords/${name}.hash.age;
        owner = "root";
        group = "root";
        mode = "0400";
      };
    })
    passwordUsers);

  # All four accounts are defined on every host (the host configurations import
  # each user module), so define the hash unconditionally. Referencing
  # `config.users.users` here to filter would recurse (this *is* users.users).
  users.users = lib.genAttrs passwordUsers (name: {
    hashedPasswordFile = config.age.secrets."password-${name}".path;
  });
}
