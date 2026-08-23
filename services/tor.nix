{ config, ... }:

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
}
