# Common user-account configuration shared by every host.
#
# `users.mutableUsers` and the per-user password hashes live in
# ./passwords.nix (declarative accounts + agenix-backed hashes).
{ ... }:

{
  imports = [ ./passwords.nix ];
}
