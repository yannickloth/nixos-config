{ config, lib, pkgs, ... }:

with lib;

let
  # Confine the kids' native game binaries: read/map system libs, write only
  # their own home + tmp, and deny all network (offline games) so a game can't
  # phone home, exfiltrate data, or be used to route around the family filter.
  # AppArmor profiles are per-executable (not per-user); this hardens the
  # shared binaries. If a game ever misbehaves, drop its profile here.
  game = pkg: bins:
    listToAttrs (map
      (bin: {
        name = "kid-${pkg}-${bin}";
        value = {
          state = "enforce";
          profile = ''
            profile kid-${pkg}-${bin} /nix/store/*-${pkg}*/bin/${bin} {
              /** mr,
              owner /home/** rw,
              /tmp/** rw,
              /var/tmp/** rw,
              /run/user/** rw,
              /dev/shm/** rw,
              /dev/null rw,
              /dev/zero rw,
              /dev/urandom rw,
              /dev/full rw,
              /dev/dri/** rw,
              /dev/input/** rw,
              /proc/sys/** r,
              /sys/** r,
            }
          '';
        };
      })
      bins);
in
{
  config = {
    security.apparmor = {
      enable = mkDefault true;
      enableCache = mkDefault true;
      policies =
        (game "extremetuxracer" [ "etr" ])
        // (game "neverball" [ "neverball" "neverputt" "mapc" ])
        // (game "supertuxkart" [ "supertuxkart" ".supertuxkart-wrapped" ])
        // (game "supertux" [ "supertux2" ])
        // (game "ktuberling" [ "ktuberling" ])
        // (game "gcompris" [ "gcompris-qt" ".gcompris-qt-wrapped" ])
        // (game "tuxpaint" [ "tuxpaint" "tuxpaint-import" ".tuxpaint-import-wrapped" "tp-magic-config" ])
        // (game "tuxtype" [ "tuxtype" ])
        // (game "luanti" [ "luanti" "luantiserver" "minetest" "minetestserver" ]);
    };
  };
}
