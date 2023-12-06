{ config, pkgs, ... }:

{
  users = {
    groups.cfo = {
      name = "cfo";
      members = [ "aeiuno" "nicky" ];
    };
  };
}
