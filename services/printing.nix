{ pkgs, ... }:

{
  programs.system-config-printer.enable = true;
  services.ipp-usb.enable = true;
  services.printing = {
    cups-pdf.enable = true; # Enable CUPS to print documents.
    # canon-cups-ufr2 is built from a non-redistributable tarball via
    # requireFile: listing it here makes every fresh host fail the build until
    # the UFR II tarball is added manually (`nix-store --add-fixed sha256
    # linux-UFRII-drv-*.tar.gz`). No Canon printer is configured in this repo,
    # so it is left out; re-add it (and the manual download step) if a Canon
    # device is ever attached.
    # cups-pdf-to-pdf is already pulled in by cups-pdf above.
    drivers = with pkgs; [
      epson-escpr2
      brgenml1lpr
      brgenml1cupswrapper
      brlaser
      cups-filters
    ];
    enable = true;
  };
}
