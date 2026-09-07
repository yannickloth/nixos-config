{ config, ... }:

{
  # enable bluetooth support on all workstations
  hardware.bluetooth.enable = true;

  # fix pairing failures (e.g. Corsair Harpoon RGB) caused by broken ERTM
  boot.extraModprobeConfig = ''
    options bluetooth disable_ertm=1
  '';

  # Keep Intel Bluetooth controllers (Intel vendor id 8087: AX2xx CNVi/USB
  # adapters, e.g. the AX210 on laptop-xps and AX211 on laptop-p16) out of USB
  # autosuspend. Autosuspend can suspend the controller mid-connection, causing
  # supervision timeouts / dropped links that look like device pairing failures.
  services.udev.extraRules = ''
    ACTION=="add", SUBSYSTEM=="usb", ATTR{idVendor}=="8087", ATTR{power/control}="on"
  '';
}
