# aaron's home. Everything a kid gets is declared once in ../kid-hm.nix (shared
# with sven, so the two accounts cannot drift); only aaron-specific extras
# belong here. aaron's own syncthing folder is /sync/aaron (rw via a named ACL,
# services/syncthing/default.nix).
{ ... }:

{
  imports = [ ../kid-hm.nix ];

  home = {
    username = "aaron";
    homeDirectory = "/home/aaron";
    # Per-kid extras go here, e.g.
    #   home.packages = [ pkgs.some-app ];
  };
}
