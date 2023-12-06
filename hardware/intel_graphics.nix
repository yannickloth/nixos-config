{ config, lib, pkgs, modulesPath, ... }:

{
  hardware = {
    opengl = {
      driSupport = true;
      enable = true;
      extraPackages = with pkgs; [
        intel-compute-runtime
        intel-media-driver
        intel-ocl
        vaapiIntel
        vaapiVdpau
        libvdpau-va-gl
        intel-compute-runtime # OpenCL filter support (hardware tone²mapping and subtitle burn-in)
      ];
    };
  };
}
