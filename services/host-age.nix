# Pinned age host identity, shared by every NixOS host.
#
# Model (zeplan.md §2): the host's age keypair is generated once in the repo
# key store (ssh-keys/hosts/<host>{,.pub}, backed up in KeePassXC and
# distributed by manual copy). Only the .pub is tracked in git; the private
# key is gitignored because Nix's git-filtered flake source cannot see
# ignored files. The build therefore verifies everything it can see, and the
# host verifies the rest at boot:
#
#   - the private key is placed on the host at
#     /etc/ssh/ssh_host_ed25519_key (mode 0600) — the documented bring-up
#     step, before the first `nixos-rebuild` of the new config;
#   - this module pins services.openssh.hostKeys to that ed25519 key, so
#     sshd-keygen self-skips (ConditionFileNotEmpty) and the key never drifts,
#     and the pinned agenix module derives age.identityPaths from hostKeys
#     (no extra wiring);
#   - the build checks, in two gates, that the host WILL be able to decrypt:
#
#     1. eval-time assertions: the tracked .pub exists, is well-formed, is
#        registered in secrets.nix, and every secret this host consumes
#        lists it as a recipient (a placeholder like TODO_* is fatal);
#     2. build-time recipient audit (environment.etc."secrets/AGE_AUDIT_OK"):
#        the recipients inside each .age header must equal the publicKeys
#        declared in secrets.nix — the probe is a toplevel dependency, so a
#        mismatch aborts the toplevel build.
#
#   - the host checks, at activation (gate 3, systemd age-secrets-guard),
#     that the placed private key actually decrypts: every secret path
#     exists non-empty under /run/agenix and every password-* file looks
#     like a SHA-512 hash. A wrong or missing private key fails sysinit
#     loudly — the failure mode that locked server-nike out in 2026-11-19
#     (agenix's own unit swallows failures and ends with `true`).
#
# The key-pair pairing (private key matches the tracked .pub) is checked
# where both files are visible: in the repo by scripts/age-audit.sh with a
# key-store argument, and on the host by gate 3 (a wrong key cannot
# decrypt, so the guard fails).
{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.services.hostAge;

  # Recipient declarations (the agenix CLI data file, not a NixOS module).
  secrets = import ../secrets.nix;

  pubPath = toString cfg.pubKey;
  pubOk = builtins.pathExists pubPath;
  pubLine = if pubOk then replaceStrings [ "\n" ] [ "" ] (readFile pubPath) else "";
  # "ssh-ed25519 <b64>" — the exact form secrets.nix stores.
  pubCore = concatStringsSep " " (take 2 (splitString " " pubLine));
  # POSIX ERE (Nix's builtins.match): no \s class; the key line is
  # "ssh-ed25519 <68 b64 chars>" plus an optional " <comment>".
  pubRegex = "^ssh-ed25519 [A-Za-z0-9+/]{68}( .*)?$";

  # Every public key value declared anywhere in secrets.nix.
  allKeys = flatten (map (v: v.publicKeys or []) (attrValues secrets));
  badKeys = filter (k: match "^ssh-ed25519 [A-Za-z0-9+/]{68}$" k == null) allKeys;

  # Secret file -> key used in secrets.nix (path relative to secrets/).
  # match groups are list elements: elemAt, not attribute access.
  relOf =
    file:
    let
      m = match "^(.*/)?secrets/(.+)$" (toString file);
    in
    assert m != null
      || throw "host-age: secret file ${toString file} is not under secrets/, so it has no secrets.nix entry to audit against";
    elemAt m 1;

  secretNames = attrNames config.age.secrets;

  # Recipients declared in secrets.nix for a secret, by its relpath.
  # builtins.hasAttr, not `secrets ? rel`: the `?` operator only takes a
  # literal name, so `? rel` would test for an attribute literally named
  # "rel" and always return false.
  keysOf =
    rel:
    if builtins.hasAttr rel secrets
    then (secrets."${rel}".publicKeys or [ ])
    else [ ];

  # For the build-time audit spec: "<file> <pub> <pub> ..." per secret this
  # host consumes, recipients taken from secrets.nix. <file> is RELATIVE to
  # the secrets/ directory: the builder cds into a store copy of secrets/
  # (${../secrets} in the runCommand), so the spec must not embed the
  # evaluation-time flake-source store path — that path is not a build input.
  specLines =
    map
      (name:
        let
          s = config.age.secrets.${name};
          rel = relOf s.file;
        in
        "${rel} ${concatStringsSep " " (keysOf rel)}")
      secretNames;

  auditSpec = pkgs.writeText "age-audit-spec" (concatStringsSep "\n" specLines);

  # bash explicitly: the script's shebang is /usr/bin/env, which does not
  # exist in the build sandbox.
  # cd ${../secrets} has two jobs: it makes the flake source (with the .age
  # files the spec points at) an input of this derivation, so the sandbox
  # builder can read them.
  audit =
    pkgs.runCommand "age-host-audit-${config.networking.hostName or "host"}" {
      nativeBuildInputs = [ pkgs.bash pkgs.openssl ];
    } ''
      cd ${../secrets}
      bash ${../scripts/age-audit.sh} host "${auditSpec}"
      echo "age audit: ${toString (length secretNames)} secrets verified for ${config.networking.hostName or "this host"}" > $out
    '';
in
{
  options.services.hostAge = {
    enable = mkEnableOption "pinned age host identity (host key generated in the repo key store)";

    pubKey = mkOption {
      type = types.path;
      description = ''
        This host's age public key in the repo key store,
        `ssh-keys/hosts/<host>.pub` (tracked in git). Its content must equal
        the value registered for this host in `secrets.nix`, and the matching
        private key must be installed on the host as
        `/etc/ssh/ssh_host_ed25519_key` (mode 0600) — see
        secrets-structure/README.md.
      '';
    };
  };

  config = mkIf cfg.enable (mkMerge [
    {
      assertions = [
        {
          assertion = pubOk;
          message = ''
            host-age: ${pubPath} does not exist.
            Generate the pair in the key store: ssh-keygen -t ed25519 -N "" -C "host ${config.networking.hostName or "?"}" -f ${removeSuffix ".pub" pubPath}
            (and copy the private key to this host as /etc/ssh/ssh_host_ed25519_key; see secrets-structure/README.md).
          '';
        }
        {
          assertion = pubOk && (match pubRegex pubLine != null);
          message = ''
            host-age: ${pubPath} is missing or not a well-formed ssh-ed25519
            public key. It must look like:
              ssh-ed25519 <68 base64 chars> [comment]
            Regenerate the pair with ssh-keygen, then run scripts/agenix-rekey.sh.
          '';
        }
        {
          assertion = badKeys == [ ];
          message = ''
            secrets.nix declares values that are not ssh-ed25519 public keys:
            ${concatMapStringsSep "\n" (k: "  ${k}") badKeys}
            Placeholder values (e.g. TODO_*) make the affected hosts
            undecryptable and every login on them fails. Replace the value
            with a real public key (secrets-structure/README.md), then re-encrypt.
          '';
        }
        {
          assertion = pubOk && (elem pubCore allKeys);
          message = ''
            host-age: ${pubPath} is not registered in secrets.nix — no secret
            lists it as a recipient, so nothing on this host can decrypt.
            Add the key and run scripts/agenix-rekey.sh, then commit.
          '';
        }
        {
          assertion =
            all
              (name:
                let
                  s = config.age.secrets.${name};
                  rel = relOf s.file;
                in
                (builtins.hasAttr rel secrets)
                && pubOk
                && (elem pubCore (keysOf rel)))
              secretNames;
          message = ''
            host-age: one or more secrets this host consumes are not encrypted
            to its key (or have no entry in secrets.nix):
            ${
              concatMapStringsSep "\n"
                (name:
                  let
                    s = config.age.secrets.${name};
                    rel = relOf s.file;
                  in
                  "  ${name} (${rel})")
                (
                  filter
                    (name:
                      let
                        s = config.age.secrets.${name};
                        rel = relOf s.file;
                      in
                      !(builtins.hasAttr rel secrets)
                      || !pubOk
                      || !(elem pubCore (keysOf rel))
                    )
                    secretNames
                )
            }
            Password logins and the affected services fail on this host.
            Run scripts/agenix-rekey.sh on a machine holding a key-store host
            key, commit the re-encrypted files, and rebuild.
          '';
        }
        {
          assertion = config.age.identityPaths != [ ];
          message = ''
            host-age: age.identityPaths is empty — agenix would have no
            identity to decrypt the host secrets. services.openssh must be
            enabled (it provides the host key this module pins).
          '';
        }
      ];
    }

    {
      # --- Pinned host key --------------------------------------------------
      # The keypair from the repo key store is the OpenSSH host key and the
      # age identity. The private half is placed at
      # /etc/ssh/ssh_host_ed25519_key by the documented bring-up step (it is
      # gitignored, so the build cannot ship it). sshd-keygen self-skips
      # (ConditionFileNotEmpty) because the file is non-empty, so no key is
      # ever generated or drifted on this host.
      # ed25519-only: keeping rsa in hostKeys would make the keygen unit skip
      # rsa generation while sshd still lists the rsa HostKey and fail.
      services.openssh.hostKeys = [
        {
          type = "ed25519";
          path = "/etc/ssh/ssh_host_ed25519_key";
        }
      ];

      environment.etc = {
        # Gate 2: the recipient audit is a dependency of the etc derivation,
        # which is a dependency of the toplevel. If the .age files disagree
        # with secrets.nix, the toplevel build fails and the switch is
        # aborted — nothing half-configured is deployed.
        "secrets/AGE_AUDIT_OK" = {
          source = audit;
          mode = "0644";
        };
      };

      # Gate 3: fail loudly at boot if agenix could not decrypt (wrong or
      # missing private key in /etc/ssh).
      systemd.services.age-secrets-guard = {
        description = "Fail loudly when agenix secrets are missing or invalid";
        wantedBy = [ "sysinit.target" ];
        after = [ "agenix-install-secrets.service" ];
        wants = [ "agenix-install-secrets.service" ];
        unitConfig.DefaultDependencies = "no";
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
        };
        script = ''
          set -u
          rc=0
          ${
            concatMapStringsSep "\n"
              (name:
                let
                  s = config.age.secrets.${name};
                  hashCheck =
                    if hasPrefix "password-" s.name
                    then ''
                       elif ! head -c 3 "${s.path}" | grep -qF '$6$'; then
                         echo "age-secrets-guard: FAIL: ${s.path} (secret '${s.name}') is not a SHA-512 password hash" >&2
                         rc=1
                    ''
                    else "";
                in
                ''
                  if [ ! -s "${s.path}" ]; then
                    echo "age-secrets-guard: FAIL: ${s.path} (secret '${s.name}') is missing or empty" >&2
                    rc=1
                  ${hashCheck}
                  fi
                ''
              )
              secretNames
          }
          if [ "$rc" -ne 0 ]; then
            echo "age-secrets-guard: agenix could not provide valid secrets (see lines above)." >&2
            echo "age-secrets-guard: cause: the host key in /etc/ssh does not match the recipients declared in secrets.nix, or a secret was never re-keyed for this host." >&2
            echo "age-secrets-guard: fix: install the key-store private key as /etc/ssh/ssh_host_ed25519_key (mode 0600), or run scripts/agenix-rekey.sh on a machine holding a key-store host key, then commit, rebuild, reboot. Password logins and secret-dependent services are broken until then." >&2
            exit 1
          fi
        '';
      };
    }
  ]);
}
