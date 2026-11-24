{ config, lib, pkgs, ... }:

with lib;
{
  security = {
    sudo = {
      execWheelOnly = true; # Only allow members of the wheel group to execute sudo by setting the executable’s permissions accordingly. This prevents users that are not members of wheel from exploiting vulnerabilities in sudo such as CVE-2021-3156.
      wheelNeedsPassword = true; # Password required for `sudo`. A successful auth caches credentials for 15 minutes (the sudo default), so interactive root calls within that window remain frictionless. AI agents running headless will fall back to the "run this manually" message in activation scripts.
    };
  };
}
