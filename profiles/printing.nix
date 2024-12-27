{ pkgs, ... }:

{
  programs.system-config-printer.enable=true;
  services.ipp-usb.enable=true;
  services.printing = {
    enable = true;
    drivers = with pkgs; [ epson-escpr2 brgenml1lpr brgenml1cupswrapper brlaser canon-cups-ufr2 ]; #hplipWithPlugin
    #cups-pdf.instances.defaultcupspdf.enable = true; 
    cups-pdf.enable = true; # Enable CUPS to print documents.
  };
}
