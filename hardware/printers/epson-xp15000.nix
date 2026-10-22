{ pkgs, ... }:
let
  xp15000 = "Epson XP 15000";
  xp15000_name = "XP-15000";
  xp15000_ip = "192.168.178.15";
in
{
  hardware = {
    printers = {
      # Declarative queue: exists for every user after each rebuild.
      ensurePrinters = [
        {
          name = xp15000_name;
          deviceUri = "ipps://${xp15000_ip}/ipp/print";
          model = "everywhere";
          description = xp15000;
          location = "B31 0 SàM";
        }
      ];
    };
  };
}

