{ config, ... }:

{
  # enable bluetooth support on all workstations
  hardware.bluetooth.enable = true;

  # fix pairing failures (e.g. Corsair Harpoon RGB) caused by broken ERTM
  boot.extraModprobeConfig = ''
    options bluetooth disable_ertm=1
  '';
}
