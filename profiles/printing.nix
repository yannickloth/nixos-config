{ pkgs, ... }:
let
  mfcl2700dw = "Brother MFC L2700DW";
  mfcl2700dw_name = "MFC-L2700DW";
  mfcl2700dw_ip = "192.168.190.27";
  xp15000 = "Epson XP 15000";
  xp15000_name = "XP-15000";
  xp15000_ip = "192.168.190.25";
in
{
  services.ipp-usb.enable=true;
  services.printing = {
    enable = true;
    # Enable CUPS to print documents.
    drivers = with pkgs; [ epson-escpr2 brgenml1lpr brgenml1cupswrapper brlaser canon-cups-ufr2 ]; #hplipWithPlugin
    #cups-pdf.instances.defaultcupspdf.enable = true;
    cups-pdf.enable = true;
  };
  programs.system-config-printer.enable=true;
  hardware = {
    printers = {
      ensureDefaultPrinter = "Brother_MFC-L2700DW";
#       ensurePrinters = [
#         {
#           name = mfcl2700dw_name;
#           deviceUri = "ipp://${mfcl2700dw_ip}/ipp";
#           model = "everywhere";
#           description = pkgs.lib.replaceStrings [ "_" ] [ " " ] mfcl2700dw;
#           location = "B31 1 Bureau";
#         }
#         {
#           name = xp15000;
#           deviceUri = "https://${xp15000_ip}:631/ipp/print";
# #           model = "escpr2";
#           model = "everywhere";
#           description = pkgs.lib.replaceStrings [ "_" ] [ " " ] xp15000;
#           location = "B31 0 SàM";
#         }
#       ];
    };
  };
}
