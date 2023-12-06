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
    # extraBackends = [ pkgs.sane-airscan pkgs.hplipWithPlugin ];
    openFirewall = true;
  };

  services.saned.enable = true;
}
