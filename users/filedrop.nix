# Shared family "filedrop": a folder every family account can read, write and
# delete files in, so passing files around is trivial. No sticky bit (anyone may
# delete anything). Setgid + the default ACL keep new files group-writable
# (filedrop) and never world-accessible.
#
# This is the ACCOUNT-to-ACCOUNT drop, on one machine, instant and offline. The
# device-to-device drop is the Syncthing folder /sync/FileDrop
# (services/syncthing/pool.nix: phones, laptops, nestor): it replicates, keeps
# versions, and needs the peers online. Keep both in the docs — parents.md
# spells out which is which, because the two names look identical in a file
# manager.
{ config, lib, ... }:

with lib;

let
  # One list defines both the group membership and who gets the ~/filedrop
  # shortcut. It used to be the same four names written twice in this file,
  # which is exactly how a new family account ends up in the group and without
  # a shortcut (or the reverse).
  members = [ "nicky" "aeiuno" "sven" "aaron" ];

  # Access + DEFAULT ACL. The `d:` entries are the whole point: an ACL rule
  # without them covers only the folder itself, so every file written into it
  # lands with its creator's umask. Measured on server-nike before they were
  # added: `touch` gave `-rw-r--r-- nicky:filedrop` — the filedrop group could
  # not write it and every other account on the machine could read it, the
  # opposite of the header above. With the default entries new files arrive
  # owner rw, group filedrop rw, others none, and new subdirectories get the
  # same plus the execute bit. Same shape as the /sync root ACL
  # (services/syncthing/default.nix `syncRootAcl`), which always had them.
  dropAcl = "u::rwx,g::rwx,o::---,d:u::rwx,d:g::rwx,d:o::---";
in
{
  users.groups.filedrop.members = members;

  systemd.tmpfiles.rules = [
    "d /filedrop 2770 root filedrop -"
    # Mode/user/group are IGNORED on a/A lines (tmpfiles.d(5)); the old rule
    # carried `2770 root filedrop` there, which looked like it was doing
    # something and did nothing. Left as `-` so nobody reads them as policy.
    "A /filedrop - - - - ${dropAcl}"
    # Recursively heal owner/mode/ACL of existing content on every activation:
    # files synced/copied in from elsewhere arrive with their own mode, and this
    # flattens them to root:filedrop 0770 so access is group-based (delete
    # allowed for everyone in the group, which is the point of the drop).
    # The `~` masks the mode against the bits already set, so documents do NOT
    # become executable and the sticky/SUID/SGID bits are dropped on
    # non-directories — systemd documents `~' as made for use with `Z'. Plain
    # `2770' here set the exec bits (and SGID) on every file in the folder.
    "Z /filedrop ~2770 root filedrop -"
  ];

  # ~/filedrop shortcut in every family home. The guards mirror linkSyncDir /
  # linkRomsDir in users/common-hm.nix, and they are not decoration: GNU `ln
  # -sfn target dir` against a REAL directory succeeds (exit 0) and creates the
  # link INSIDE it, so without the -L/-e checks a user's own ~/filedrop
  # directory silently ends up with a nested ~/filedrop/filedrop and never
  # becomes the shortcut.
  home-manager.sharedModules = [
    ({ config, pkgs, lib, ... }: {
      # `pkgs` has to be bound by THIS lambda: home-manager passes it in its own
      # module args, and it is not in scope from this file's outer module.
      config = mkIf (builtins.elem config.home.username members) {
        home.activation.linkFiledropDir = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
          if [ -L "$HOME/filedrop" ]; then
            $DRY_RUN_CMD ${pkgs.coreutils}/bin/ln -sfn /filedrop "$HOME/filedrop"
          elif [ -e "$HOME/filedrop" ]; then
            # A real directory/file here is the user's own data, not a mistake:
            # never clobber it, and never hand it to `ln -sfn`.
            echo "warning: $HOME/filedrop exists and is not a symlink; leaving it alone" >&2
          elif [ -d /filedrop ]; then
            $DRY_RUN_CMD ${pkgs.coreutils}/bin/ln -s /filedrop "$HOME/filedrop"
          else
            echo "warning: /filedrop does not exist; not creating ~/filedrop symlink" >&2
          fi
        '';
      };
    })
  ];
}
