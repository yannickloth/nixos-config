{ config, lib, pkgs, ... }:

with lib;
{
  services.onedrive = {
    enable = false;
};
}
