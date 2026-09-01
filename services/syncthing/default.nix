# Syncthing as a single system service for the whole family.
#
# One daemon runs for all users (system user `syncthing`); nicky and aeiuno get
# access to the data via the `syncthing` group and to the web UI via a shared
# GUI password. Kids have no access to the family data: sven/aaron only get
# named-user ACLs on /sync/sven and /sync/aaron respectively (plus traverse
# access on the /sync root), so they can reach their own folder and nothing else.
#
# The folder/device set is the single source of truth in `./pool.nix`: every
# host syncs all 34 folders to nestor and the other laptops (replication /
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

  # The full device list for this host: itself plus every peer.
  devices =
    mapAttrs (name: dev: { inherit name; id = dev.id; })
      pool.devices;

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
      (filterAttrs (_: f: elem selfName f.devices) pool.folders);

  # Per-host secrets dir for the device cert/key. agenix decrypts the cert/key
  # here from the git-committed .age files (see age.secrets below).
  secretsDir = "/etc/nixos/secrets/syncthing/${selfName}";
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
      guiAddress = "0.0.0.0:8384"; # LAN: family members reach the web UI
      openDefaultPorts = true;
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
      };
      settings.devices = devices;
      settings.folders = folders;
      settings.options = {
        localAnnounceEnabled = true;
        relaysEnabled = true;
        urAccepted = -1;
      };
    };

    # --- Access control ---
    # Parents reach /sync via the syncthing group; kids are not in that group.
    # sven/aaron reach /sync only to traverse into their own folder
    # (/sync/sven, /sync/aaron), where a named ACL grants them rw. The web UI
    # needs the shared GUI password, which is provisioned by services/secrets.nix
    # from secrets/.
    users.groups.syncthing.members = [ "nicky" "aeiuno" ];

    networking.firewall.allowedTCPPorts = [
      8384 # syncthing web UI
    ];

    systemd.tmpfiles.rules = [
      # 2770 (no "others"): only the syncthing group (parents) can reach /sync.
      "d /sync 2770 syncthing syncthing -"
      # Default ACL: new synced files inherit group rwx and are never
      # world-readable. sven/aaron get traverse-only (--x) so they can reach
      # their own folder below without listing the rest of /sync.
      "A /sync 2770 syncthing syncthing - u::rwx,u:sven:--x,u:aaron:--x,g::rwx,o::---"
      # Per-kid folders: setgid (2770) so new content inherits group syncthing
      # (parents + syncthing daemon both rw), plus a named ACL so the kid is rw.
      "d /sync/sven 2770 syncthing syncthing -"
      "A /sync/sven 2770 syncthing syncthing - u::rwx,u:sven:rwx,g::rwx,o::---"
      "d /sync/aaron 2770 syncthing syncthing -"
      "A /sync/aaron 2770 syncthing syncthing - u::rwx,u:aaron:rwx,g::rwx,o::---"
      "d /var/lib/syncthing 0700 syncthing syncthing -"
    ];

    # Files synced in from other hosts arrive with their original permissions
    # (often owner-only), so the default ACL above is not enough — the parent
    # users must be able to read/write everything. On activation, recursively
    # add a group rwx ACL to all existing content under /sync so nicky/aeiuno
    # (members of the syncthing group) can access everything. The same is done
    # for the kids on their own folders. Idempotent.
    system.activationScripts.syncthing-acl = stringAfter [ "users" "groups" ] ''
      if [ -d /sync ]; then
        ${pkgs.acl}/bin/setfacl -R -m g::rwx /sync 2>/dev/null || true
        ${pkgs.acl}/bin/setfacl -m u:sven:--x,u:aaron:--x /sync 2>/dev/null || true

        # Per-kid folders + their XDG dirs: create if missing (syncthing only
        # creates the folder root at first start; nothing creates the XDG
        # subdirs), setgid + group rw, and grant the kid rw (also as a default
        # ACL so new synced content stays writable by the kid). The setgid bit
        # makes new files inherit group syncthing, so the daemon and the parents
        # (group) can always reach them.
        ${concatMapStringsSep "\n" (d: ''
          for xd in Desktop Documents Downloads Music Pictures Public Templates Videos; do
            mkdir -p /sync/${d}/"$xd"
            chmod 2770 /sync/${d}/"$xd"
            chown syncthing:syncthing /sync/${d}/"$xd"
            ${pkgs.acl}/bin/setfacl -m u:${d}:rwx /sync/${d}/"$xd" 2>/dev/null || true
            ${pkgs.acl}/bin/setfacl -d -m u:${d}:rwx /sync/${d}/"$xd" 2>/dev/null || true
          done
          chmod 2770 /sync/${d}
          chown syncthing:syncthing /sync/${d}
          ${pkgs.acl}/bin/setfacl -m u:${d}:rwx /sync/${d} 2>/dev/null || true
          ${pkgs.acl}/bin/setfacl -d -m u:${d}:rwx /sync/${d} 2>/dev/null || true
          ${pkgs.acl}/bin/setfacl -R -m u:${d}:rwx /sync/${d} 2>/dev/null || true
          ${pkgs.acl}/bin/setfacl -R -d -m u:${d}:rwx /sync/${d} 2>/dev/null || true
        '') [ "sven" "aaron" ]}
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
    # Because the .age files are encrypted to the union of all host/user keys,
    # a reinstall can decrypt with any restored private key; the device ID is
    # preserved by restoring this host's key from KeePassXC. See
    # secrets-structure/README.md for the reinstall workflow.
    #
    # Only declared when a pre-generated identity exists for this host; otherwise
    # syncthing generates its own on first boot (see hasSyncthingIdentity).
    age.secrets.syncthing-cert = lib.mkIf hasSyncthingIdentity {
      file = ../../secrets/syncthing/${selfName}/cert.pem.age;
      path = "${secretsDir}/cert.pem";
      mode = "0644";
      owner = "root";
      group = "root";
    };
    age.secrets.syncthing-key = lib.mkIf hasSyncthingIdentity {
      file = ../../secrets/syncthing/${selfName}/key.pem.age;
      path = "${secretsDir}/key.pem";
      mode = "0600";
      owner = "root";
      group = "root";
    };
  };
}
