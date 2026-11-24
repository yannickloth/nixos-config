# sven's home. Everything a kid gets is declared once in ../kid-hm.nix (shared
# with aaron, so the two accounts cannot drift); only sven-specific extras
# belong here. sven's own syncthing folder is /sync/sven (rw via a named ACL,
# services/syncthing/default.nix).
{ ... }:

{
  imports = [ ../kid-hm.nix ];

  home = {
    username = "sven";
    homeDirectory = "/home/sven";
    # Per-kid extras go here, e.g.
    #   home.packages = [ pkgs.some-app ];
  };
}
