{ pkgs, ... }:
let
  mfcl2700dw_ip = "192.168.190.27";
  mfcl2700dw_model = "MFC-L2700DW";
in
{
  hardware.sane = {
    enable = true;
    brscan4 = {
        enable = true;
        netDevices = {
          MFCL2700DW = { model = "${mfcl2700dw_model}"; ip = "${mfcl2700dw_ip}"; };
        };
      };
    disabledDefaultBackends = [ "escl" ]; # disable the default escl backend, to avoid finding scanners twice (once with escl, once with airscan)
    extraBackends = [ pkgs.sane-airscan # for Apple AirScan scanners and Microsoft WSD
                      #pkgs.hplipWithPlugin
    ];
    openFirewall = true;
  };

  services.ipp-usb.enable=true; # enable ipp-usb, a daemon to turn an USB printer/scanner supporting IPP everywhere (aka AirPrint, WSD, AirScan) into a locally accessible network printer/scanner
  services.saned.enable = true; # Enable saned network daemon for remote connection to scanners.
}
