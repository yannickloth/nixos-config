{ config, lib, ... }:

let
  # Single source of truth for the proxy/control ports: the tor settings, the
  # exported environment and the kids' block must never drift apart.
  socksPort = 9050;
  controlPort = 9051;
  torBrowserPort = 9150;

  kidNames = [ "sven" "aaron" ];
  helpers = import ../lib;
  kidUsers = lib.filter
    (u: builtins.hasAttr u config.users.users && config.users.users.${u}.uid != null)
    kidNames;
  # Fail closed: a renamed/removed kid or an auto-allocated (null) uid must not
  # silently drop the block below.
  missingKids = helpers.missingUsersOrUid config.users.users kidNames;
  kidUids = lib.map (u: toString config.users.users.${u}.uid) kidUsers;
in
{
  assertions = [
    {
      assertion = missingKids == [ ];
      message = "services/tor.nix: ${toString missingKids} must exist with an explicit uid (the Tor kid-block keys on it)";
    }
    {
      assertion = config.networking.nftables.enable;
      message = "services/tor.nix: the kids' Tor block requires networking.nftables.enable";
    }
  ];

  services.tor = {
    enable = true;
    settings = {
      ControlPort = controlPort;
      # Without an authentication method any local process can drive the
      # daemon; the nftables kid-block is not authentication.
      CookieAuthentication = true;
      SocksPort = socksPort;
    };
    client = {
      enable = true;
      # SOCKS-on-demand only: do NOT route all system traffic through Tor
      # via the transparent proxy (heavy on RAM/CPU, affects everything).
      transparentProxy.enable = false;
      # dns.enable = true; # tied to the transparent proxy; leave off
    };
  };

  environment.variables = {
    TOR_SOCKS_PORT = toString socksPort;
    TOR_CONTROL_PORT = toString controlPort;
    TOR_SKIP_LAUNCH = "1";
  };

  # Kids must not be able to route around the family DNS filter through the
  # local Tor SOCKS proxy (or a Tor Browser's port). Declarative nftables output
  # chain; `reject` is a final verdict, so a later chain cannot re-allow it.
  # This keys on the kids' numeric UIDs, so users/{sven,aaron}.nix pin explicit
  # stable uids (an auto-allocated uid would be null at build time).
  networking.nftables.tables."nixos-fw".content =
    lib.mkAfter (lib.optionalString (kidUids != [ ]) (
      helpers.torBlockRules {
        uids = kidUids;
        socksPort = socksPort;
        controlPort = controlPort;
        browserPort = torBrowserPort;
      }
    ));
}
