{ pkgs, ... }:
let
  mfcl2700dw = "Brother MFC L2700DW";
  mfcl2700dw_name = "MFC-L2700DW";
  mfcl2700dw_ip = "192.168.178.27";
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
      # Declarative queue: exists for every user after each rebuild.
      # Traditional CUPS driver instead of "everywhere" (driverless IPP): the
      # brlaser PPD ships this exact model (brl2700w.ppd) and is already
      # installed by services/printing.nix. The value is passed verbatim to
      # `lpadmin -m`, so it must match a `lpinfo -m` line. Brother's
      # proprietary generic driver (`brother-BrGenML1-cups-en.ppd`,
      # brgenml1cupswrapper) is the alternative if brlaser misbehaves.
      ensurePrinters = [
        {
          name = mfcl2700dw_name;
          deviceUri = "ipp://${mfcl2700dw_ip}/ipp";
          model = "drv:///brlaser.drv/brl2700w.ppd";
          description = pkgs.lib.replaceStrings [ "_" ] [ " " ] mfcl2700dw;
          location = "B31 1 Bureau";
        }
      ];
    };
  };
}
