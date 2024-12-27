{ pkgs, ... }:
let
  xp15000 = "Epson XP 15000";
  xp15000_name = "XP-15000";
  xp15000_ip = "192.168.190.25";
in
{
  hardware = {
    printers = {
      #       ensurePrinters = [
      #         {
      #           name = xp15000;
      #           deviceUri = "https://${xp15000_ip}:631/ipp/print";
      # #           model = "escpr2";
      #           model = "everywhere";
      #           description = pkgs.lib.replaceStrings [ "_" ] [ " " ] xp15000;
      #           location = "B31 0 SàM";
      #         }
      # ];
    };
  };
}

