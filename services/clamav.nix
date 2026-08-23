{ config, lib, pkgs, ... }:

with lib;
{
  # ClamAV antivirus: run the scanning daemon AND keep the signature DB updated.
  services.clamav = {
    daemon.enable = true;
    updater.enable = true;
  };
}
