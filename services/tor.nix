{ config, lib, pkgs, ... }:

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
  # local Tor SOCKS proxy (or a Tor Browser's port). Block their UIDs from the
  # Tor ports; parents are unaffected. Runs after user accounts are created.
  #
  # Uses iptables (nixpkgs' iptables is iptables-nft, so this is nftables under
  # the hood) at activation time because the UID is only known then. A
  # declarative networking.nftables chain would need `users.users.<n>.uid` set
  # explicitly — sven/aaron have null uids (auto-allocated at activation), so
  # `toString null` would render an invalid `meta skuid { , }`. Only convert to
  # a declarative chain after giving the kids explicit, stable uids.
  system.activationScripts.tor-block-kids = {
    deps = [ "users" ];
    text = ''
      for u in sven aaron; do
        if uid=$(${pkgs.coreutils}/bin/id -u "$u" 2>/dev/null); then
          ${pkgs.iptables}/bin/iptables -C OUTPUT -m owner --uid-owner "$uid" -d 127.0.0.1 -p tcp -m multiport --dports 9050,9051,9150 -j REJECT 2>/dev/null \
            || ${pkgs.iptables}/bin/iptables -A OUTPUT -m owner --uid-owner "$uid" -d 127.0.0.1 -p tcp -m multiport --dports 9050,9051,9150 -j REJECT
        fi
      done
    '';
  };
}
