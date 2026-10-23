# Pure helper functions extracted from the modules so they can be unit-tested
# with nix-unit (tests/unit.nix) and snapshotted with namaka
# (tests/snapshots.nix) without evaluating a full system.
#
# Keep this file dependency-free (builtins only): it must stay importable from
# modules, packages and the test derivations alike.
rec {
  # "app/org.kde.krita/x86_64/stable" -> "org.kde.krita"
  # A malformed ref fails with a readable message instead of an opaque elemAt
  # error (this used to break the whole host evaluation).
  parseAppRef =
    ref:
    let
      parts = builtins.filter builtins.isString (builtins.split "/" ref);
    in
    if builtins.length parts >= 2 then
      builtins.elemAt parts 1
    else
      throw "apps.flatpak: malformed app ref '${ref}' (expected app/<id>/<arch>/<branch>)";

  # Users in `candidates` that actually exist in the `users` attrset.
  filterExistingUsers = users: candidates: builtins.filter (u: builtins.hasAttr u users) candidates;

  # Users in `candidates` that do NOT exist in the `users` attrset.
  missingUsers = users: candidates: builtins.filter (u: !(builtins.hasAttr u users)) candidates;

  # Users missing, or present without an explicit uid (auto-allocated uids are
  # null at build time, which breaks rules that key on them).
  missingUsersOrUid =
    users: candidates:
    builtins.filter (u: !(builtins.hasAttr u users) || users.${u}.uid == null) candidates;

  # Subset of `candidates` that are declared folders in `folders`.
  filterExistingFolders = folders: candidates: builtins.filter (f: builtins.hasAttr f folders) candidates;

  # Stable stamp for the expensive recursive ACL repair: same folder/kid sets
  # (in any order) produce the same hash.
  aclStamp =
    folders: kids:
    builtins.hashString "sha256" (builtins.concatStringsSep ":" (builtins.sort builtins.lessThan (folders ++ kids)));

  # Home directory for a user, falling back to /home/<name> when the account is
  # not declared on this host.
  homePathFor =
    users: name:
    let
      user = users.${name} or null;
    in
    if user == null || user.home == null then "/home/${name}" else user.home;

  # Scalar formatting for the strata config patcher: null means "not set" and
  # is passed as the literal "none" (the patcher's sentinel).
  optArg = v: if v == null then "none" else toString v;
  jsonArg = v: if v == null then "none" else builtins.toJSON v;

  # quota-tools' `setquota -P` block limits are in 1024-byte units.
  gibToKiB = gib: gib * 1024 * 1024;

  # Private source ranges used by the scoped service rules (LAN + CGNAT +
  # link-local for IPv4; ULA + link-local for IPv6).
  privateV4 = "192.168.0.0/16, 10.0.0.0/8, 172.16.0.0/12, 100.64.0.0/10";
  privateV4LinkLocal = "${privateV4}, 169.254.0.0/16";
  privateV6 = "fe80::/10, fc00::/7";

  # nftables accept rules for one service's ports from private ranges only
  # (avahi/steam/sonos). A protocol with an empty port list emits nothing.
  privateNetRules =
    {
      tcp ? [ ],
      udp ? [ ],
      v4 ? privateV4,
    }:
    let
      mk = family: proto: saddr: ports: "${family} saddr { ${saddr} } ${proto} dport { ${builtins.concatStringsSep ", " ports} } accept";
      perProto = proto: ports: [
        (mk "ip" proto v4 ports)
        (mk "ip6" proto privateV6 ports)
      ];
    in
    builtins.concatStringsSep "\n" (
      (if tcp == [ ] then [ ] else perProto "tcp" tcp)
      ++ (if udp == [ ] then [ ] else perProto "udp" udp)
    );

  # Tor: block the kids' uids from the local SOCKS/control/Tor-Browser ports.
  torBlockRules =
    {
      uids,
      socksPort,
      controlPort,
      browserPort,
    }:
    let
      uidSet = builtins.concatStringsSep ", " (builtins.map toString uids);
      ports = "${toString socksPort}, ${toString controlPort}, ${toString browserPort}";
    in
    ''
      chain tor-block-kids {
        type filter hook output priority 0; policy accept;
        meta skuid { ${uidSet} } ip daddr 127.0.0.0/8 tcp dport { ${ports} } reject with tcp reset
        meta skuid { ${uidSet} } ip6 daddr ::1 tcp dport { ${ports} } reject with tcp reset
      }
    '';

  # Syncthing: the subset of declared folders that list this host as a peer.
  selectFoldersForHost =
    folders: self:
    builtins.listToAttrs (
      builtins.filter (x: x != null) (
        builtins.map (
          name:
          if builtins.elem self (folders.${name}.devices or [ ]) then
            {
              inherit name;
              value = folders.${name};
            }
          else
            null
        ) (builtins.attrNames folders)
      )
    );

  # Per-user README targets (home directory + file name).
  readmeTargets =
    users: files:
    builtins.map (user: {
      inherit user;
      target = "${homePathFor users user}/README.md";
    }) (builtins.attrNames files);

  # Flatpak: app ids of a list of refs (used to match cfg.overrides).
  appIdsOf = refs: builtins.map parseAppRef refs;

  # Shell snippet installing the family SSH identities (used by
  # services/ssh-user-keys.nix and snapshotted by the tests).
  sshKeyInstallScript =
    {
      installBin,
      keys,
    }:
    builtins.concatStringsSep "\n" (
      builtins.map (k: ''
        if [ -r "${k.secret}" ]; then
          ${installBin} -d -m 0700 -o ${k.user} -g users "${k.home}/.ssh"
          ${installBin} -m 0600 -o ${k.user} -g users "${k.secret}" "${k.home}/.ssh/agenix_${k.user}"
        else
          echo "ssh-user-keys: ${k.secret} missing; skipping ${k.user}" >&2
        fi
      '') keys
    );
}
