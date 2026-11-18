# Software fan control (fancontrol from lm_sensors).
#
# Import this module on hosts where the stock/BIOS fan curve is too
# aggressive (typically desktops with a stock Intel cooler). On laptops,
# thermald + power-profiles-daemon + the UEFI fan profile are usually
# sufficient and fancontrol is not needed.
#
# Setup (one-time, on the target machine):
#   1. Run `sensors-detect` and answer YES to probing all default sensors.
#   2. Run `sudo pwmconfig` and follow the interactive prompts
#      (it stops each fan briefly to identify which header it drives).
#   3. Copy the generated /etc/conf.d/fancontrol content into
#      `hardware.fancontrol.config` in the host's configuration file.
#   4. Rebuild: `sudo nixos-rebuild switch`.
#
# The `lm_sensors` package (sensors, pwmconfig, fancontrol, sensors-detect)
# is already installed via roles/system.nix on all hosts.

{ config, lib, pkgs, ... }:

{
  hardware.fancontrol.enable = true;
}
