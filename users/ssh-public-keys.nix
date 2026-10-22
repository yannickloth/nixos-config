# Public halves of the family SSH identities.
#
# These are the same key pairs as ssh-keys/users/<name> (gitignored, private
# halves) and the `user-*` agenix recipients in secrets.nix. Public keys are
# safe to commit; the private halves only exist as the agenix-encrypted
# secrets/ssh-user-<name>.key.age files (encrypted to the host keys, see
# services/ssh-user-keys.nix).
#
# Keeping them here (instead of reading ssh-keys/*.pub at build time) matters:
# flakes build from the git tree, where ssh-keys/** is gitignored.
{
  nicky = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIL7qyn3G5ztyNoQ6u4RZ1nJZaDNHcQRGhKaVj0i8pC8m user nicky";
  aeiuno = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIASyK+Od8c/gEwvvdtz1Lovd/qnomAeCRr+cPmhn6qvQ user aeiuno";
  sven = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGEsqIouG7nwHEqH0W7r0ywiUtD7em/xKHjKV1PpmFbp user sven";
  aaron = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPtH5ncJyvw7qKZ5tQODeNsM0QVvmh9Layw9PJT8JoyN user aaron";
}
