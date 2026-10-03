{ config, lib, ... }:

{
  services.tor = {
    enable = true;
    settings.ControlPort = 9051;
    client = {
      enable = true;
      # SOCKS-on-demand only: do NOT route all system traffic through Tor
      # via the transparent proxy (heavy on RAM/CPU, affects everything).
      transparentProxy.enable = false;
      # dns.enable = true; # tied to the transparent proxy; leave off
    };
  };

  environment.variables = {
    TOR_SOCKS_PORT = "9050";
    TOR_CONTROL_PORT = "9051";
    TOR_SKIP_LAUNCH = "1";
  };

  # Kids must not be able to route around the family DNS filter through the
  # local Tor SOCKS proxy (or a Tor Browser's port). Declarative nftables output
  # chain; `reject` is a final verdict, so a later chain cannot re-allow it.
  # This keys on the kids' numeric UIDs, so users/{sven,aaron}.nix pin explicit
  # stable uids (an auto-allocated uid would be null at build time).
  networking.nftables.tables."nixos-fw".content =
    let
      kidNames = [ "sven" "aaron" ];
      kidUsers = lib.filter
        (u: builtins.hasAttr u config.users.users && config.users.users.${u}.uid != null)
        kidNames;
      kidUids = lib.map (u: toString config.users.users.${u}.uid) kidUsers;
    in
    lib.mkAfter (lib.optionalString (kidUids != [ ]) ''
      chain tor-block-kids {
        type filter hook output priority 0; policy accept;
        meta skuid { ${lib.concatStringsSep ", " kidUids} } ip daddr 127.0.0.1 tcp dport { 9050, 9051, 9150 } reject with tcp reset
      }
    '');
}
