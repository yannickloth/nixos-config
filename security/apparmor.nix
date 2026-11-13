{ config, lib, pkgs, ... }:

with lib;

let
  # Confine the kids' native game binaries: read/map system files, write only
  # their own home + tmp, and deny all network (offline games) so a game can't
  # phone home, exfiltrate data, or be used to route around the family filter.
  # AppArmor profiles are per-executable (not per-user); this hardens the
  # shared binaries. If a game ever misbehaves, drop its profile here.
  #
  # Notes on the rules below:
  #  - no blanket `/** mr`: only the paths a game actually needs are readable;
  #  - `ix` (inherit-exec) lets a game run its own helper binaries while
  #    staying under the same confinement (never `ux`, which would escape it);
  #  - `/dev/input/** r` (not rw): games read input; they have no business
  #    writing to it;
  #  - `deny network,` is what actually enables network mediation for the
  #    profile; without any network rule AppArmor skips network checks.
  game = pkg: bins:
    listToAttrs (map
      (bin: {
        name = "kid-${pkg}-${bin}";
        value = {
          state = "enforce";
          profile = ''
            profile kid-${pkg}-${bin} /nix/store/*-${pkg}*/bin/${bin} {
              # Read/execute the store (game data, libraries, helper binaries)
              /nix/store/** rmix,
              /run/opengl-driver/** rm,
              /run/current-system/sw/** rmix,
              /usr/** rmix,
              # Configuration and system metadata (read-only)
              /etc/** r,
              /proc/** r,
              /sys/** r,
              # Per-user data and scratch space
              owner /home/** rwmk,
              /tmp/** rwmk,
              /var/tmp/** rwmk,
              /run/user/** rwmk,
              /dev/shm/** rwmk,
              # Devices
              /dev/null rw,
              /dev/zero rw,
              /dev/urandom r,
              /dev/random r,
              /dev/full rw,
              /dev/dri/** rw,
              /dev/input/** r,
              # No networking at all (offline games); the deny rule enables
              # network mediation for this profile.
              deny network,
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
