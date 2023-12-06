{ config, ... }:

{
    services.tor = {
      enable = true;
      settings.ControlPort = 9051;
      client = {
        enable = true;
        dns.enable = true;
        transparentProxy.enable = true;
      };
    };

    environment.variables = {
      TOR_SOCKS_PORT = "9050";
      TOR_CONTROL_PORT = "9051";
      TOR_SKIP_LAUNCH = "1";
    };
}
