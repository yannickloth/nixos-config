{ pkgs, ... }:

{
  programs.system-config-printer.enable=true;
  services.ipp-usb.enable=true;
  services.printing = {
    cups-pdf.enable = true; # Enable CUPS to print documents.
    drivers = with pkgs; [ epson-escpr2 brgenml1lpr brgenml1cupswrapper brlaser canon-cups-ufr2 cups-filters cups-pdf-to-pdf ]; #hplipWithPlugin
    enable = true;
  };
}
