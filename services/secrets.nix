# Secret provisioning from the repo's gitignored `secrets/` folder.
#
# `secrets/` (repo root) is the single source of truth for every secret the
# config expects (see secrets-structure/README.md for the inventory). This
# module copies them into the conventional runtime paths that services read,
# so the repo folder is the one place to drop/update secrets.
#
# - /etc/secrets/syncthing-gui-password  (Syncthing web UI, group syncthing)
# - /etc/secrets/open-webui.env          (family AI chat, group secrets)
# - /etc/nixos/cifs/<mount>.secrets      (per-mount CIFS client credentials)
#
# All secrets in `secrets/` are gitignored; only their *expected layout* is
# tracked under `secrets-structure/`.

{ config, lib, pkgs, ... }:

with lib;

let
  # Gitignored repo folder holding the real secret files.
  secretsDir = "/home/nicky/code/nixos-config/secrets";

  # Every CIFS *client* mount uses its own credentials file. They live in
  # secrets/cifs/<mount>.secrets and are provisioned to
  # /etc/nixos/cifs/<mount>.secrets. To add a mount: drop its credentials file
  # in secrets/cifs/ and reference it from the mount's cifs-<name>.nix module.
  cifsSecretsDir = secretsDir + "/cifs";
  # Shell loop copies any secrets/cifs/*.secrets to /etc/nixos/cifs/.
  cifsProvision = ''
    install -d -o root -g root -m 0755 /etc/nixos/cifs
    for f in ${lib.escapeShellArg (cifsSecretsDir + "/*.secrets")}; do
      [[ -e "$f" ]] || continue
      name="$(basename "$f")"
      install -o root -g root -m 0600 "$f" "/etc/nixos/cifs/$name"
      echo "cifs: provisioned /etc/nixos/cifs/$name"
    done
  '';
in
{
  config = {
    # Runtime directories for the services that read these secrets. The `secrets`
    # group (also defined by services/ai-chat.nix with the same members) is
    # declared here so /etc/secrets exists on any host.
    users.groups.secrets = {
      members = [ "nicky" "aeiuno" ];
    };

    systemd.tmpfiles.rules = [
      # 2770 + group rw so nicky/aeiuno can edit secrets without sudo.
      "d /etc/secrets 2770 root secrets -"
    ];

    # Copy each secret from `secrets/` into its runtime path, if present.
    # Idempotent; missing sources are skipped (the file simply isn't provisioned).
    system.activationScripts.secrets = stringAfter [ "users" ] ''
      install -d -o root -g root -m 0755 /etc/nixos
      # The GUI password target group only exists when syncthing is enabled.
      ${lib.optionalString config.services.syncthing.enable ''
        ${lib.optionalString (builtins.pathExists (secretsDir + "/syncthing-gui-password")) ''
          install -o root -g syncthing -m 0640 \
            ${lib.escapeShellArg (secretsDir + "/syncthing-gui-password")} \
            /etc/secrets/syncthing-gui-password
        ''}
      ''}
      ${lib.optionalString (builtins.pathExists (secretsDir + "/open-webui.env")) ''
        install -o root -g secrets -m 0660 \
          ${lib.escapeShellArg (secretsDir + "/open-webui.env")} \
          /etc/secrets/open-webui.env
      ''}
      ${cifsProvision}
    '';
  };
}
