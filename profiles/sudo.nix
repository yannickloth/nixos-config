{ config, lib, pkgs, ... }:

with lib;
{
  security = {
    sudo = {
      execWheelOnly = true; # Only allow members of the wheel group to execute sudo by setting the executable’s permissions accordingly. This prevents users that are not members of wheel from exploiting vulnerabilities in sudo such as CVE-2021-3156.
      wheelNeedsPassword = false; # Whether users of the wheel group must provide a password to run commands as super user via sudo.
    };
  };
}
