# Syncthing as a single system service for the whole family.
#
# One daemon runs for all users (system user `syncthing`); nicky and aeiuno get
# access to the data via the `syncthing` group and to the web UI via a shared
# GUI password. Kids have no access to /sync.
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

  # Per-host secrets dir for the device cert/key.
  secretsDir = "/etc/nixos/secrets/syncthing/${selfName}";
  # Gitignored staging copy inside the repo, if present (see .gitignore).
  # Carries a pre-generated identity to a fresh host when the working tree
  # (including gitignored files) is copied over.
  stagingDir = "/home/nicky/code/nixos-config/secrets/syncthing/${selfName}";
in
{
  options.services.syncthing = {
    self = mkOption {
      type = types.str;
      description = "This host's device name (a key of services/syncthing pool devices).";
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
      cert = "${secretsDir}/cert.pem";
      key = "${secretsDir}/key.pem";
      guiPasswordFile = "/etc/secrets/syncthing-gui-password";
      settings.devices = devices;
      settings.folders = folders;
      settings.options = {
        localAnnounceEnabled = true;
        relaysEnabled = true;
        urAccepted = -1;
      };
    };

    # --- Access control ---
    # Parents reach /sync via the syncthing group; kids are excluded (2770 +
    # ACL: group rwx, no "others"). The web UI needs the shared GUI password.
    users.groups.syncthing.members = [ "nicky" "aeiuno" ];
    # /etc/secrets group (also used by services/ai-chat.nix); kept here so the
    # syncthing GUI password dir exists even when ai-chat is disabled.
    users.groups.secrets = {
      members = [ "nicky" "aeiuno" ];
    };

    networking.firewall.allowedTCPPorts = [
      8384 # syncthing web UI
    ];

    systemd.tmpfiles.rules = [
      # 2770 (no "others"): only the syncthing group (parents) can reach /sync.
      "d /sync 2770 syncthing syncthing -"
      # Default ACL: new synced files inherit group rwx and are never
      # world-readable.
      "A /sync 2770 syncthing syncthing - u::rwx,g::rwx,o::---"
      "d /var/lib/syncthing 0700 syncthing syncthing -"
      # Shared GUI password (single credential for nicky + aeiuno).
      "d /etc/secrets 2770 root secrets -"
      "f /etc/secrets/syncthing-gui-password 0660 root syncthing -"
    ];

    # --- Automated device identity ---
    # Ensure the local cert/key exist before syncthing starts. Priority:
    #   1. An already-present cert in the secrets dir (kept — idempotent; also
    #      where a pre-generated cert dropped from KeePass is picked up).
    #   2. A gitignored staging copy in the repo (secrets/syncthing/<self>/),
    #      so a pre-generated identity rides along when the working tree is
    #      copied to a new host.
    #   3. An existing /var/lib/syncthing cert (already-registered hosts keep
    #      their device ID, e.g. laptop-hera).
    #   4. Generate a fresh identity (new hosts without a provided cert).
    # Runs once, as root.
    system.activationScripts.syncthing-keys = stringAfter [ "users" ] ''
      mkdir -p ${lib.escapeShellArg secretsDir}
      chmod 0700 ${lib.escapeShellArg secretsDir}
      if [[ ! -e ${lib.escapeShellArg secretsDir}/cert.pem || ! -e ${lib.escapeShellArg secretsDir}/key.pem ]]; then
        if [[ -e ${lib.escapeShellArg stagingDir}/cert.pem && -e ${lib.escapeShellArg stagingDir}/key.pem ]]; then
          cp -p ${lib.escapeShellArg stagingDir}/cert.pem ${lib.escapeShellArg secretsDir}/cert.pem
          cp -p ${lib.escapeShellArg stagingDir}/key.pem ${lib.escapeShellArg secretsDir}/key.pem
          echo "syncthing: using pre-generated device cert/key from staging"
        elif [[ -e /var/lib/syncthing/cert.pem && -e /var/lib/syncthing/key.pem ]]; then
          cp -p /var/lib/syncthing/cert.pem ${lib.escapeShellArg secretsDir}/cert.pem
          cp -p /var/lib/syncthing/key.pem ${lib.escapeShellArg secretsDir}/key.pem
          echo "syncthing: preserved existing device cert/key from /var/lib/syncthing"
        else
          # Generate a fresh identity into secretsDir (cert.pem + key.pem).
          ${lib.getExe pkgs.syncthing} generate --home=${lib.escapeShellArg secretsDir}
          echo "syncthing: generated new device cert/key for ${selfName}"
        fi
        chown root:root ${lib.escapeShellArg secretsDir}/cert.pem ${lib.escapeShellArg secretsDir}/key.pem
        chmod 0644 ${lib.escapeShellArg secretsDir}/cert.pem
        chmod 0600 ${lib.escapeShellArg secretsDir}/key.pem
      fi
    '';
  };
}
