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
    # old provisioning script, kept so existing consumers and the ai-chat module
    # continue to work unchanged).
    users.groups.secrets = {
      members = [ "nicky" "aeiuno" ];
    };

    systemd.tmpfiles.rules = [
      # 2770 + group rw so nicky/aeiuno can edit secrets without sudo.
      "d /etc/secrets 2770 root secrets -"
    ];

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

      # Family AI-chat provider keys (Open WebUI), read via EnvironmentFile.
      open-webui-env = {
        file = ../secrets/open-webui.env.age;
        path = "/etc/secrets/open-webui.env";
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
