{ pkgs, ... }:
{
  environment.systemPackages = with pkgs; [
    # naps2 # Scan documents to PDF and more, as simply as possible. # Comment out because saving to PDF fails as well as OCR with tesseract.
    simple-scan
  ];
  nixpkgs.config.permittedInsecurePackages = [
    "dotnet-sdk-6.0.428" # marked as insecure, refusing to evaluate, needed for naps2
  ];

  hardware = {
    sane = {
      enable = true;
      # eSCL is a driverless scanning protocol. It is an http(s) and xml based for all communiction. the standard was created by Mopria.
      # eSCL is the default communication method found in MacOS, and is often referred to as AirPrint Scanning or AirScan.
      # On Linux there are two different back-ends for SANE to support eSCL: SANE-AirScan and SANE-eSCL.
      # SANE-AirScan also supports the WSD protocol, thus it supports more than SANE-eSCL.
      disabledDefaultBackends = [ "escl" ]; # disable the default sane-escl backend, to avoid finding scanners twice (once with sane-escl, once with sane-airscan)
      extraBackends = [
        pkgs.sane-airscan # for Apple AirScan scanners and Microsoft WSD
        #pkgs.hplipWithPlugin
      ];
      openFirewall = true;
    };
  };

  services.ipp-usb.enable = true; # enable ipp-usb, a daemon to turn an USB printer/scanner supporting IPP everywhere (aka AirPrint, WSD, AirScan) into a locally accessible network printer/scanner
  services.saned.enable = true; # Enable saned network daemon for remote connection to scanners.
}
