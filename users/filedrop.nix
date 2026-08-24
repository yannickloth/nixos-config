# Shared family "filedrop": a folder every family account can read, write and
# delete files in, so passing files around is trivial. No sticky bit (anyone may
# delete anything). Setgid + default ACL keep new files group-writable (filedrop)
# and never world-accessible.
{ config, lib, ... }:

with lib;

{
  users.groups.filedrop = {
    members = [ "nicky" "aeiuno" "sven" "aaron" ];
  };

  systemd.tmpfiles.rules = [
    "d /filedrop 2770 root filedrop -"
    # Default ACL (mirrors the /steamlib pattern): new files get owner rwx,
    # group filedrop rwx, no access for others.
    "A /filedrop 2770 root filedrop - u::rwx,g::rwx,o::---"
    # Recursively heal owner/mode/setgid of existing content on every boot.
    "Z /filedrop 2770 root filedrop -"
  ];

  # ~/filedrop symlink in every home (same pattern as ~/sync in common-hm.nix).
  home-manager.sharedModules = [
    ({ config, lib, ... }: {
      config = mkIf (builtins.elem config.home.username [ "nicky" "aeiuno" "sven" "aaron" ]) {
        home.activation.linkFiledropDir = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
          if [ -d /filedrop ]; then
            $DRY_RUN_CMD ln -sfn /filedrop "$HOME/filedrop"
          else
            echo "warning: /filedrop does not exist; not creating ~/filedrop symlink"
          fi
        '';
      };
    })
  ];
}
