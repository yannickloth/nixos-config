# Syncthing as a single system service for the whole family.
#
# One daemon runs for all users (system user `syncthing`); nicky and aeiuno get
# access to the data via the `syncthing` group and to the web UI via a shared
# GUI password. Kids have no access to the family data: sven/aaron only get
# read on the /sync root (they see the folder names), named-user ACLs on
# /sync/sven and /sync/aaron respectively (rw), and rX on the public roms
# library (~/roms for every user). The other folders stay unreadable: the kids
# inherit traverse-only (--x) on them, so they can cd but never list or read.
#
# The folder/device set is the single source of truth in `./pool.nix`: every
# host syncs all 37 folders to nestor and the other laptops (replication /
# closest-to-backup). A host only needs to set `services.syncthing.self` to its
# device name; folders, devices, and the per-host cert/key are derived here.
#
# Device identity: the local node's cert/key are auto-provisioned into
# /etc/nixos/secrets/syncthing/<self>/ by an activation script — preferring a
# gitignored pre-generated copy in the repo, then an existing /var/lib/syncthing
# cert (so an already-registered host like laptop-hera keeps its device ID),
# else generating a fresh identity. This gives every host a stable device ID
# without manual copying. Pre-generated IDs are committed in pool.nix; the
# private cert/key stay out of git (see .gitignore, KeePass backup).

{ config, lib, pkgs, ... }:

with lib;

let
  pool = import ./pool.nix;
  cfg = config.services.syncthing;

  selfName = cfg.self;

  # The full device list for this host. The local node stays in the map: the
  # nixpkgs module resolves folder peers through settings.devices by name (self
  # included), and Syncthing itself ignores its own ID as a remote device.
  devices =
    mapAttrs (name: dev: { inherit name; id = dev.id; }) pool.devices;

  # Folders this host should sync: those whose share matrix includes self.
  # Each is shared with exactly the peers listed in the matrix.
  folders =
    mapAttrs
      (label: f: {
        inherit (f) id;
        label = label;
        type = "sendreceive";
        rescanIntervalS = 3600;
        versioning = {
          type = "staggered";
          params.maxAge = "31536000"; # 1 year
        };
        path = "${cfg.dataDir}/${label}";
        devices = f.devices;
      })
      (helpers.selectFoldersForHost pool.folders selfName);

  # Person folders synced on this host (used for the XDG subdirs and the
  # recursive ACL repair below).
  helpers = import ../../lib;
  syncedPersonFolders = helpers.filterExistingFolders folders [ "yannick" "christine" "sven" "aaron" ];
  # Stamp for the expensive recursive ACL repair: it only needs to run when the
  # folder set changes (or on a fresh install), not on every switch.
  aclStamp = helpers.aclStamp syncedPersonFolders [ "sven" "aaron" ];
  # Full ACL (access + default) for the /sync root, shared between the
  # tmpfiles rule (boot) and the activation script (every switch, and the
  # full-tree repair below): the parents' group is rwx; the kids can list the
  # root (r-x) so ~/sync is a working entry point, but NEW top-level folders
  # inherit the default entries, where the kids stay traverse-only (--x) —
  # a folder synced in from another host must not be readable for them.
  syncRootAcl = "u::rwx,u:sven:r-x,u:aaron:r-x,g::rwx,o::---,d:u::rwx,d:u:sven:--x,d:u:aaron:--x,d:g::rwx,d:o::---";

  # Per-host identity dir. agenix decrypts the cert/key here from the
  # git-committed .age files (see age.secrets below); it lives outside the
  # configuration checkout so a `git add -A` can never commit the plaintext
  # private key.
  secretsDir = "/var/lib/syncthing/identity";
  # True when this host has a pre-generated syncthing identity committed as
  # secrets/syncthing/<self>/cert.pem.age. Hosts without one (e.g. a brand-new
  # laptop) skip the cert/key agenix secrets and let syncthing generate its own
  # identity on first boot. Tracked .age files are visible to pure evaluation.
  hasSyncthingIdentity = builtins.pathExists (../../secrets/syncthing/${selfName}/cert.pem.age);
in
{
  options.services.syncthing = {
    self = mkOption {
      type = types.str;
      description = "This host's device name (a key of services/syncthing pool devices).";
    };
    guiUser = mkOption {
      type = types.str;
      default = "nicky";
      description = "Username for the Syncthing web UI login. The password is read from guiPasswordFile (the secret).";
    };
  };

  config = {
    services.syncthing = {
      enable = true;
      user = "syncthing";
      group = "syncthing";
      dataDir = "/sync";
      configDir = "/var/lib/syncthing";
      # Listener on all interfaces: the GUI is reachable from the LAN/Wi-Fi
      # (family devices) and from the tailnet. Binding to a specific address
      # breaks as soon as DHCP hands out another one.
      guiAddress = "0.0.0.0:8384";
      # Not openDefaultPorts: the firewall rules below are explicit.
      openDefaultPorts = false;
      overrideDevices = true; # strict: only the declared set is kept
      overrideFolders = true; # strict: only the declared set is kept
      cert = lib.mkIf hasSyncthingIdentity "${secretsDir}/cert.pem";
      key = lib.mkIf hasSyncthingIdentity "${secretsDir}/key.pem";
      guiPasswordFile = "/etc/secrets/syncthing-gui-password";
      settings.gui = {
        # Single shared GUI account (username + password) for nicky + aeiuno;
        # Syncthing's web UI supports only one login per instance. The password
        # comes from guiPasswordFile; the username is set via the guiUser option.
        user = cfg.guiUser;
        # Enforce HTTPS: plain-HTTP requests are redirected. Syncthing
        # generates a self-signed certificate in the config dir on first start
        # (https-cert.pem/https-key.pem); replace those with a real certificate
        # for the hosts you browse from. This keeps the shared password and
        # session cookie off the wire on LAN/Wi-Fi.
        tls = true;
      };
      settings.devices = devices;
      settings.folders = folders;
      settings.options = {
        localAnnounceEnabled = true;
        relaysEnabled = true;
        urAccepted = -1;
      };
    };

    # GUI on 8384 (LAN/Wi-Fi + tailnet, HTTPS enforced above) and the
    # device-ID-authenticated sync port on 22000 (LAN and tailnet).
    networking.firewall = {
      allowedTCPPorts = [ 8384 22000 ];
      allowedUDPPorts = [ 22000 ];
    };

    # --- Access control ---
    # Parents reach /sync via the syncthing group; kids are not in that group.
    # sven/aaron can list the /sync root (r-x) to find their folder, have rw on
    # their own folder (/sync/sven, /sync/aaron via named ACLs), and read the
    # public roms library (~/roms -> /sync/90-99 - Public stuff/roms). The
    # other folders stay unreadable: the kids inherit traverse-only (--x) on
    # them, so they can cd into them but never list or read their contents.
    # The web UI needs the shared GUI password, which is provisioned by
    # services/secrets.nix from secrets/.
    users.groups.syncthing.members = [ "nicky" "aeiuno" ];

    # NOTE: the firewall ports live in the `networking.firewall` block next to
    # the services.syncthing settings above (GUI 8384 on LAN/Wi-Fi + tailnet,
    # sync 22000).

    systemd.tmpfiles.rules = [
      # 2770 (no "others"): only the syncthing group (parents) can reach /sync.
      "d /sync 2770 syncthing syncthing -"
      # The root's full ACL lives in `syncRootAcl` (let block) so the boot
      # rule and the activation script cannot drift apart. The `d:` entries
      # are the *default* ACL entries that make new content inherit these
      # permissions (without them only existing files are covered).
      "A /sync 2770 syncthing syncthing - ${syncRootAcl}"
      # Per-kid folders: setgid (2770) so new content inherits group syncthing
      # (parents + syncthing daemon both rw), plus a named ACL so the kid is rw.
      "d /sync/sven 2770 syncthing syncthing -"
      "A /sync/sven 2770 syncthing syncthing - u::rwx,u:sven:rwx,g::rwx,o::---,d:u::rwx,d:u:sven:rwx,d:g::rwx,d:o::---"
      "d /sync/aaron 2770 syncthing syncthing -"
      "A /sync/aaron 2770 syncthing syncthing - u::rwx,u:aaron:rwx,g::rwx,o::---,d:u::rwx,d:u:aaron:rwx,d:g::rwx,d:o::---"
      # RetroArch ROM library (games/games.nix points RetroArch's
      # system_directory at roms/BIOS): every user must be able to read it, so
      # the kids get read+traverse here (files r, dirs rx). Quoted path: the
      # synced folder name contains spaces (systemd tmpfiles quoting).
      "d \"/sync/90-99 - Public stuff/roms\" 2770 syncthing syncthing -"
      "A \"/sync/90-99 - Public stuff/roms\" - - - - u::rwx,u:sven:rX,u:aaron:rX,g::rwx,o::---,d:u::rwx,d:u:sven:rX,d:u:aaron:rX,d:g::rwx,d:o::---"
      "d /var/lib/syncthing 0700 syncthing syncthing -"
      # Device identity (agenix writes cert.pem/key.pem here as 0640
      # root:syncthing, so the daemon can read them).
      "d /var/lib/syncthing/identity 0750 root syncthing -"
    ];

    # Files synced in from other hosts arrive with their original permissions
    # (often owner-only), so the default ACL above is not enough — the parent
    # users must be able to read/write everything. On activation, recursively
    # add a group rwx ACL to all existing content under /sync so nicky/aeiuno
    # (members of the syncthing group) can access everything. The same is done
    # for the kids on their own folders. Idempotent.
    system.activationScripts.syncthing-acl = stringAfter [ "users" "groups" "syncthing-data-dir" ] ''
      ACL_STAMP="${aclStamp}"
      if [ -d /sync ]; then
        # The root's full ACL (access + default, see syncRootAcl) on every
        # switch: self-heals if anything clobbers it between switches.
        ${pkgs.acl}/bin/setfacl -m ${syncRootAcl} /sync 2>/dev/null || true
        # Traverse for the kids on the public-stuff folder so they can reach
        # the roms library (rX below); the folder itself stays unlistable for
        # them (it also holds non-public files).
        ${pkgs.acl}/bin/setfacl -m u:sven:--x,u:aaron:--x "/sync/90-99 - Public stuff" 2>/dev/null || true

        # XDG subdirs for every user's syncthing folder: create if missing
        # (syncthing only creates the folder root at first start; nothing
        # creates the XDG subdirs). setgid + group rw so the daemon and the
        # parents (syncthing group) can always reach them; the default ACL on
        # /sync propagates group rw to new content. The dir list must match the
        # xdg.userDirs lists in users/*/[user]-hm.nix (which point at
        # ~/sync/<folder>): add new dirs in both places.
        ${concatMapStringsSep "\n" (folder: ''
          for xd in Desktop Documents Downloads Music Pictures Projects Public Templates Videos; do
            mkdir -p /sync/${folder}/"$xd"
            chmod 2770 /sync/${folder}/"$xd"
            chown syncthing:syncthing /sync/${folder}/"$xd"
          done
          chmod 2770 /sync/${folder}
          chown syncthing:syncthing /sync/${folder}
        '') syncedPersonFolders}

        # RetroArch ROM library: create the skeleton (see roms/README.md) and
        # re-grant the kids' read ACLs on every switch. Deliberately NOT inside
        # the .acl-stamp block: unlike the whole /sync tree this folder is
        # small, so the recursive pass is cheap and any ROM dropped in from
        # another host between switches gets fixed on the next one.
        romsDir="/sync/90-99 - Public stuff/roms"
        mkdir -p "$romsDir"
        chmod 2770 "$romsDir"
        chown syncthing:syncthing "$romsDir"
        for sysDir in BIOS NES SNES "Mega Drive" "Master System" "Game Gear" \
                      "Game Boy" "Game Boy Advance" "Nintendo 64" "PC Engine" \
                      "WonderSwan" "Neo Geo Pocket" "Virtual Boy" "Atari Lynx" \
                      "Atari Jaguar"; do
          mkdir -p "$romsDir/$sysDir/Homebrew"
          chmod 2770 "$romsDir/$sysDir" "$romsDir/$sysDir/Homebrew"
          chown syncthing:syncthing "$romsDir/$sysDir" "$romsDir/$sysDir/Homebrew"
        done
        ${pkgs.acl}/bin/setfacl -R -m u:sven:rX,u:aaron:rX "$romsDir"
        ${pkgs.acl}/bin/setfacl -R -d -m u:sven:rX,u:aaron:rX "$romsDir"

        # Expensive part: full-tree ACL repair (can take minutes on large
        # photo/music trees). Runs when the .acl-strip-v1 marker is missing
        # (ONE-TIME repair: the tree inherited from the original laptop-p16
        # setup carries r-x named entries for the kids on every top-level
        # folder, leaking the parents' folder/file NAMES to them) or when the
        # folder set changes (.acl-stamp). Deleting either file under
        # /var/lib/syncthing forces a full repair.
        #
        # The repair strips the kids' named entries from the whole tree and
        # re-grants exactly the intended set, so the end state is identical
        # no matter what the tree contained: parents' group rwx everywhere,
        # the kids rw on their own folder, rX under the roms, nothing else.
        if [ ! -f /var/lib/syncthing/.acl-strip-v1 ] \
          || [ "$(cat /var/lib/syncthing/.acl-stamp 2>/dev/null)" != "$ACL_STAMP" ]; then
          # Strip the kids' named entries wherever they leaked in. Files
          # without an entry make setfacl error per file — expected and
          # suppressed; the pass continues.
          ${pkgs.acl}/bin/setfacl -R -x u:sven /sync 2>/dev/null || true
          ${pkgs.acl}/bin/setfacl -R -x u:aaron /sync 2>/dev/null || true
          ${pkgs.acl}/bin/setfacl -R -d -x u:sven /sync 2>/dev/null || true
          ${pkgs.acl}/bin/setfacl -R -d -x u:aaron /sync 2>/dev/null || true

          # Re-establish the root (the strip above removed its named entries)
          # and the kids' traverse on the public-stuff folder (see above).
          ${pkgs.acl}/bin/setfacl -m ${syncRootAcl} /sync 2>/dev/null || true
          ${pkgs.acl}/bin/setfacl -m u:sven:--x,u:aaron:--x "/sync/90-99 - Public stuff" 2>/dev/null || true

          # Parents: recursive group rwx (synced files arrive with their
          # original permissions, often owner-only).
          ${pkgs.acl}/bin/setfacl -R -m g::rwx /sync 2>/dev/null || true

          # Kids are not in the syncthing group, so grant each of them rw on
          # their own folder only (named + default ACL, so new synced content
          # stays writable by them). Adults reach their folders through the
          # group, so they need no per-user ACL.
          ${concatMapStringsSep "\n" (d: ''
            ${pkgs.acl}/bin/setfacl -m u:${d}:rwx /sync/${d} 2>/dev/null || true
            ${pkgs.acl}/bin/setfacl -d -m u:${d}:rwx /sync/${d} 2>/dev/null || true
            ${pkgs.acl}/bin/setfacl -R -m u:${d}:rwx /sync/${d} 2>/dev/null || true
            ${pkgs.acl}/bin/setfacl -R -d -m u:${d}:rwx /sync/${d} 2>/dev/null || true
          '') [ "sven" "aaron" ]}

          # Roms: rX for the kids — the strip above removed what the
          # per-switch pass set earlier in this script.
          ${pkgs.acl}/bin/setfacl -R -m u:sven:rX,u:aaron:rX "$romsDir" 2>/dev/null || true
          ${pkgs.acl}/bin/setfacl -R -d -m u:sven:rX,u:aaron:rX "$romsDir" 2>/dev/null || true

          ${pkgs.coreutils}/bin/mkdir -p /var/lib/syncthing
          ${pkgs.coreutils}/bin/touch /var/lib/syncthing/.acl-strip-v1
          ${pkgs.coreutils}/bin/printf '%s\n' "$ACL_STAMP" > /var/lib/syncthing/.acl-stamp
        fi
      fi
    '';

    # Create /sync at activation time, not only via tmpfiles at boot, so that
    # ~/sync symlinks are correct from the very first `nixos-rebuild switch`
    # (tmpfiles only runs at boot, which is after the switch). This runs before
    # the home-manager-<user> boot services, which is what users/common-hm.nix
    # linkSyncDir relies on. tmpfiles still enforces ownership/ACLs at boot.
    system.activationScripts.syncthing-data-dir = {
      deps = [ "groups" "users" ];
      text = ''
        mkdir -p /sync
        chmod 2770 /sync
        chown syncthing:syncthing /sync
        # Link each syncthing group member's ~/sync right after /sync exists.
        # Mirrors users/common-hm.nix linkSyncDir (needed for standalone
        # home-manager, e.g. CachyOS laptop-p16).
        ${concatMapStringsSep "\n" (user: ''
          home='${escapeShellArg config.users.users.${user}.home}'
          if [ -d "$home" ]; then
            ln -sfn /sync "$home/sync"
          fi
        '') (config.users.groups.syncthing.members or [ ])}
      '';
    };

    # --- Device identity via agenix ---
    # The Syncthing device cert/key for this host are decrypted from the git-
    # committed .age files at activation time (using this host's SSH host key).
    # The .age files are encrypted to THIS host's key only (see secrets.nix), so
    # no other host or user can impersonate this device. The device ID is
    # preserved on reinstall by restoring this host's private key from
    # KeePassXC. See secrets-structure/README.md for the reinstall workflow.
    #
    # Only declared when a pre-generated identity exists for this host; otherwise
    # syncthing generates its own on first boot (see hasSyncthingIdentity).
    age.secrets.syncthing-cert = lib.mkIf hasSyncthingIdentity {
      file = ../../secrets/syncthing/${selfName}/cert.pem.age;
      path = "${secretsDir}/cert.pem";
      mode = "0640";
      owner = "root";
      group = "syncthing";
    };
    age.secrets.syncthing-key = lib.mkIf hasSyncthingIdentity {
      file = ../../secrets/syncthing/${selfName}/key.pem.age;
      path = "${secretsDir}/key.pem";
      mode = "0640";
      owner = "root";
      group = "syncthing";
    };
  };
}
