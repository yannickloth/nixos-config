# Distribute the family SSH identities (the same keys that are agenix
# recipients) to every NixOS host, and authorize their public halves.
#
# Why: key-based SSH logins currently require copying ~/.ssh/agenix_<user> to
# each machine by hand, which is why password authentication is still enabled.
# With this module every `nixos-rebuild switch` installs the user's identity as
# ~/.ssh/agenix_<user> (0600, owned by the user) and puts the matching public
# key in that account's authorized_keys.
#
# Host private keys (ssh-keys/hosts/*) are deliberately NOT distributed: they
# identify the machine (SSH host keys) and belong only in /etc/ssh.
#
# Private keys live only as agenix secrets (secrets/ssh-user-<user>.key.age,
# encrypted to the host keys). agenix decrypts them to /run/agenix (root-only);
# this unit copies them into the home with the right owner and mode. The copy
# goes through /run/agenix rather than letting agenix write into $HOME because
# agenix's `path` would be a root-owned file (or a symlink to one) that the
# user cannot read.
{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.services.sshUserKeys;

  # Only users that actually exist on this host. This module does not define
  # users.users itself (the authorized_keys live in each user's module), so
  # probing the option here cannot recurse.
  keyUsers = (import ../lib).filterExistingUsers config.users.users [ "nicky" "aeiuno" "sven" "aaron" ];
in
{
  options.services.sshUserKeys = {
    enable = mkEnableOption "distribution of the family SSH identities and authorized_keys";
  };

  config = mkIf cfg.enable {
    assertions = [
      {
        assertion = config.age.identityPaths != [ ];
        message = "services.sshUserKeys: age.identityPaths must be set (openssh host keys).";
      }
    ];

    # One age secret per user identity, decrypted to /run/agenix (root-only).
    age.secrets = listToAttrs (
      map
        (u: nameValuePair "ssh-user-${u}" {
          file = ../secrets/ssh-user-${u}.key.age;
          mode = "0400";
          owner = "root";
          group = "root";
        })
        keyUsers
    );

    # Install the private halves into the users' ~/.ssh. Runs at multi-user (so
    # /home is mounted and the accounts exist) and is restarted when a key
    # changes.
    systemd.services.ssh-user-keys = {
      description = "Install family SSH identities into user ~/.ssh";
      wantedBy = [ "multi-user.target" ];
      after = [ "local-fs.target" "agenix-install-secrets.service" ];
      restartTriggers = map (u: ../secrets/ssh-user-${u}.key.age) keyUsers;
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = (import ../lib).sshKeyInstallScript {
        installBin = "${pkgs.coreutils}/bin/install";
        keys = map (u: {
          user = u;
          home = config.users.users.${u}.home;
          secret = "/run/agenix/ssh-user-${u}";
        }) keyUsers;
      };
    };
  };
}
