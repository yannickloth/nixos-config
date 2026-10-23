# nix-unit tests for the pure helpers in lib/default.nix.
# Run with: nix-unit tests/unit.nix   (or `nix flake check`)
let
  helpers = import ../lib;
  # Minimal stand-ins for the NixOS `users.users` attrset.
  users = {
    alice = { uid = 1000; home = "/home/alice"; };
    bob = { uid = 1001; home = "/var/home/bob"; };
    carol = { uid = null; home = "/home/carol"; };
  };
in
{
  testParseAppRefId = {
    expr = helpers.parseAppRef "app/org.kde.krita/x86_64/stable";
    expected = "org.kde.krita";
  };

  testParseAppRefNestedNamespace = {
    expr = helpers.parseAppRef "runtime/org.freedesktop.Platform/x86_64/24.08";
    expected = "org.freedesktop.Platform";
  };

  testFilterExistingUsers = {
    expr = helpers.filterExistingUsers users [ "alice" "nobody" "bob" ];
    expected = [ "alice" "bob" ];
  };

  testMissingUsers = {
    expr = helpers.missingUsers users [ "alice" "nobody" ];
    expected = [ "nobody" ];
  };

  testMissingUsersOrUid = {
    # carol exists but has no explicit uid; the Tor block needs numeric uids.
    expr = helpers.missingUsersOrUid users [ "alice" "carol" "nobody" ];
    expected = [ "carol" "nobody" ];
  };

  testFilterExistingFolders = {
    expr = helpers.filterExistingFolders { "A" = { }; "B" = { }; } [ "A" "C" ];
    expected = [ "A" ];
  };

  testAclStampOrderIndependent = {
    expr = helpers.aclStamp [ "b" "a" ] [ "sven" ] == helpers.aclStamp [ "a" "b" ] [ "sven" ];
    expected = true;
  };

  testAclStampChangesWithFolders = {
    expr = helpers.aclStamp [ "a" ] [ "sven" ] == helpers.aclStamp [ "a" "b" ] [ "sven" ];
    expected = false;
  };

  testHomePathCustom = {
    expr = helpers.homePathFor users "bob";
    expected = "/var/home/bob";
  };

  testHomePathFallback = {
    expr = helpers.homePathFor users "nobody";
    expected = "/home/nobody";
  };

  testOptArgNull = {
    expr = helpers.optArg null;
    expected = "none";
  };

  testOptArgNumber = {
    expr = helpers.optArg 12;
    expected = "12";
  };

  testJsonArgFloatRendering = {
    expr = helpers.jsonArg 0.35;
    expected = "0.35";
  };

  testJsonArgNull = {
    expr = helpers.jsonArg null;
    expected = "none";
  };

  testParseAppRefMalformed = {
    expr = helpers.parseAppRef "not-an-app-ref";
    expectedError.type = "ThrownError";
    expectedError.msg = "malformed app ref";
  };

  testGibToKiB = {
    # 50 GiB in quota-tools' 1024-byte block units.
    expr = helpers.gibToKiB 50;
    expected = 52428800;
  };

  testPrivateNetRulesTcpOnly = {
    expr = builtins.length (builtins.filter builtins.isString (builtins.split "\n" (helpers.privateNetRules { tcp = [ "22" ]; })));
    expected = 2;
  };

  testPrivateNetRulesEmpty = {
    expr = helpers.privateNetRules { };
    expected = "";
  };

  testPrivateNetRulesProtocols = {
    expr = builtins.match ".*ip saddr.*tcp dport.*ip6 saddr.*tcp dport.*udp dport.*" (
      helpers.privateNetRules { tcp = [ "1" ]; udp = [ "2" ]; }
    ) != null;
    expected = true;
  };

  testTorBlockRules = {
    expr = builtins.match ".*meta skuid.*1000, 1001.*127.0.0.0/8.*::1.*9050, 9051, 9150.*" (
      helpers.torBlockRules { uids = [ 1000 1001 ]; socksPort = 9050; controlPort = 9051; browserPort = 9150; }
    ) != null;
    expected = true;
  };

  testSelectFoldersForHost = {
    expr = builtins.attrNames (helpers.selectFoldersForHost {
      A = { devices = [ "xps" "hera" ]; };
      B = { devices = [ "hera" ]; };
    } "xps");
    expected = [ "A" ];
  };

  testReadmeTargets = {
    expr = helpers.readmeTargets { bob = { home = "/var/home/bob"; }; } { bob = /dev/null; };
    expected = [ { user = "bob"; target = "/var/home/bob/README.md"; } ];
  };

  testAppIdsOf = {
    expr = helpers.appIdsOf [ "app/org.kde.krita/x86_64/stable" "app/org.gnome.Cheese/x86_64/stable" ];
    expected = [ "org.kde.krita" "org.gnome.Cheese" ];
  };

  testSshKeyInstallScript = {
    expr = builtins.match ".*install -m 0600 -o alice -g users.*agenix_alice.*" (
      helpers.sshKeyInstallScript {
        installBin = "install";
        keys = [ { user = "alice"; home = "/home/alice"; secret = "/run/agenix/ssh-user-alice"; } ];
      }
    ) != null;
    expected = true;
  };
}
