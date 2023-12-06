{ config, lib, pkgs, modulesPath, ... }:

{
  imports =
    [ (modulesPath + "/installer/scan/not-detected.nix")
    ];
  boot = {
    kernelModules = [ "xpad" ];
    extraModulePackages = [
      (config.boot.kernelPackages.callPackage ../packages/xpad.nix {})
    ];
  };
  # udev rules for xpad
  services.udev.extraRules = ''
    ACTION=="add", \
	  ATTRS{idVendor}=="2dc8", \
	  ATTRS{idProduct}=="3106", \
	  RUN+="${pkgs.kmod}/bin/modprobe xpad", \
	  RUN+="${pkgs.bash}/bin/sh -c 'echo 2dc8 3106 > /sys/bus/usb/drivers/xpad/new_id'"
  '';
}
