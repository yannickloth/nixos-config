{ config, lib, pkgs, modulesPath, ... }:

{
  hardware = {
    cpu.intel.updateMicrocode = true; # Update the CPU microcode for Intel processors.
  };
}
