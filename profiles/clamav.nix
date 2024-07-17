{ config, lib, pkgs, ... }:

with lib;
{
  # Enable the ClamAV service and keep the database up to date
  services.clamav = {
    daemon.enable = false;
    updater.enable = true;
  };
}
