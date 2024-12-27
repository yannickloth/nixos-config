{ pkgs, ... }:
let
  mfcl2700dw = "Brother MFC L2700DW";
  mfcl2700dw_name = "MFC-L2700DW";
  mfcl2700dw_ip = "192.168.190.27";
  mfcl2700dw_model = "MFC-L2700DW";
in
{
  hardware = {
    sane = {
      brscan4 = {
        enable = true;
        netDevices = {
          MFCL2700DW = { model = "${mfcl2700dw_model}"; ip = "${mfcl2700dw_ip}"; };
        };
      };
    };
    printers = {
      ensureDefaultPrinter = mfcl2700dw_name;
      #       ensurePrinters = [
      #         {
      #           name = mfcl2700dw_name;
      #           deviceUri = "ipp://${mfcl2700dw_ip}/ipp";
      #           model = "everywhere";
      #           description = pkgs.lib.replaceStrings [ "_" ] [ " " ] mfcl2700dw;
      #           location = "B31 1 Bureau";
      #         }
      #       ];
    };
  };
}
