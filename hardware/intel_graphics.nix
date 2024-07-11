{ config, lib, pkgs, modulesPath, ... }:

{
  hardware = {
    graphics = {
      enable = true;
      enable32Bit = true;
      extraPackages = with pkgs; [
        intel-compute-runtime # OpenCL filter support (hardware tone²mapping and subtitle burn-in)
        intel-media-driver
        intel-ocl
        (if (lib.versionOlder (lib.versions.majorMinor lib.version) "23.11") then vaapiIntel else intel-vaapi-driver)
        libva-vdpau-driver
        libvdpau-va-gl
        vaapi-intel-hybrid
      ];
    };
  };
}
