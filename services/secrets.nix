# Secret provisioning via agenix (age-encrypted secrets, committed to git).
#
# `secrets/` (repo root) holds the encrypted `.age` files; `secrets.nix` lists
# the recipient SSH keys. agenix decrypts each secret on the target host using
# that host's SSH host key (`age.identityPaths`), then mounts it at the path the
# consuming service reads. No plaintext is ever committed or copied at build
# time — decryption happens at activation on the machine itself.
#
# See secrets-structure/README.md for the full workflow (rekey, backup, new
# host bring-up).

{ config, lib, pkgs, ... }:

with lib;

{
  config = {
    # Runtime directory for secrets shared by services (same group model as the
    # old provisioning script, kept so existing consumers continue to work
    # unchanged).
    users.groups.secrets = {
      members = [ "nicky" "aeiuno" ];
    };

    systemd.tmpfiles.rules = [
      # 3770 + group rw so nicky/aeiuno can still edit secrets in place, but
      # the sticky bit stops them from unlinking/replacing root-owned files
      # (which would defeat the per-secret owner/mode settings).
      "d /etc/secrets 3770 root secrets -"
    ]
    # The Syncthing secret is 0640 root:syncthing, but this directory is
    # group-traversable only for `secrets`. Give the syncthing user the
    # traverse bit so the daemon can open its own password file.
    ++ lib.optionals config.services.syncthing.enable [
      "A /etc/secrets - - - - u:syncthing:--x"
    ];

    # Versioned instructions for the secrets dir (linked into /etc/secrets).
    environment.etc."secrets/README.md".source = ./secrets-README.md;

    # agenix secrets. Each decrypts on this host (using its SSH host key) to the
    # conventional runtime path the consuming service reads.
    age.secrets = {
      # Syncthing web-UI password. Only mounted when syncthing is enabled.
      syncthing-gui-password = mkIf config.services.syncthing.enable {
        file = ../secrets/syncthing-gui-password.age;
        path = "/etc/secrets/syncthing-gui-password";
        mode = "0640";
        owner = "root";
        group = "syncthing";
      };

      # Shared LLM provider keys for opencode (OPENAI_API_KEYS JSON). The
      # home-manager activation in users/opencode.nix materializes the
      # per-provider key files from it (see /etc/secrets/README.md).
      opencode-keys-env = {
        file = ../secrets/opencode-keys.env.age;
        path = "/etc/secrets/opencode-keys.env";
        mode = "0660";
        owner = "root";
        group = "secrets";
      };

      # CIFS client credentials for the nestor mount. NOTE: services/cifs-nestor.nix
      # is not currently imported by any host; enable this once the mount is wired up.
      # cifs-nestor = {
      #   file = ../secrets/cifs/nestor.secrets.age;
      #   path = "/etc/nixos/cifs/nestor.secrets";
      #   mode = "0600";
      #   owner = "root";
      #   group = "root";
      # };
    };
  };
}
