builtins.toJSON (map
  ((import ../../../lib).homePathFor {
    alice = { home = "/home/alice"; };
    bob = { home = "/var/home/bob"; };
  })
  [ "alice" "bob" "nobody" ])
