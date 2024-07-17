{ config, lib, pkgs, modulesPath, ... }:
# Read this: https://wiki.archlinux.org/title/Hardware_video_acceleration#Comparison_tables
{
  environment.systemPackages = with pkgs; [
      intel-gpu-tools # Tools for development and testing of the Intel DRM driver. (provides intel_gpu_top)
      libva-utils
      vdpauinfo
      vulkan-tools
    ];
  hardware = {
    graphics = {
      enable = true;
      enable32Bit = true;
      extraPackages = with pkgs; [
        intel-compute-runtime # OpenCL filter support (hardware tone mapping and subtitle burn-in)
        intel-media-driver
        intel-ocl
        (if (lib.versionOlder (lib.versions.majorMinor lib.version) "23.11") then vaapiIntel else intel-vaapi-driver)
        libdrm # Direct Rendering Manager library and headers
        libva # Implementation for VA-API (Video Acceleration API)
        libvdpau-va-gl # VDPAU implementation using VAAPI backend
      ];
      extraPackages32 = with pkgs.pkgsi686Linux; [ 
        intel-media-driver
        (if (lib.versionOlder (lib.versions.majorMinor lib.version) "23.11") then vaapiIntel else intel-vaapi-driver)
        libdrm # Direct Rendering Manager library and headers
        libva # Implementation for VA-API (Video Acceleration API)
        libvdpau-va-gl # VDPAU implementation using VAAPI backend
      ];
    };
  };
  services.xserver.videoDrivers = [ "modesetting" ];
  security.wrappers = {
    intel-gpu-top = {
      owner = "root";
      group = "cfo";
      capabilities = "CAP_PERFMON+pe";
      source = "${pkgs.intel-gpu-tools.out}/bin/intel_gpu_top";
    };
  };
}
