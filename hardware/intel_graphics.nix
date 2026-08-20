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
      extraPackages = lib.mkForce(with pkgs; [
        intel-compute-runtime # OpenCL filter support (hardware tone mapping and subtitle burn-in)
        intel-media-driver # LIBVA_DRIVER_NAME=iHD
        # intel-ocl # proprietary, not needed, conflicts with intel-compute-runtime, which is the modern alternative
        
        
        #(pkgs.lowPrio intel-compute-runtime-legacy1) # Tell Nix that if legacy drops in uninvited, the modern driver wins.
        (if (lib.versionOlder (lib.versions.majorMinor lib.version) "23.11") then vaapiIntel else intel-vaapi-driver)
        libdrm # Direct Rendering Manager library and headers
        libva # Implementation for VA-API (Video Acceleration API)
        libvdpau-va-gl # VDPAU implementation using VAAPI backend
      ]);
      extraPackages32 = with pkgs.pkgsi686Linux; [ 
        intel-media-driver # LIBVA_DRIVER_NAME=iHD
        (if (lib.versionOlder (lib.versions.majorMinor lib.version) "23.11") then vaapiIntel else intel-vaapi-driver)
        libdrm # Direct Rendering Manager library and headers
        libva # Implementation for VA-API (Video Acceleration API)
        libvdpau-va-gl # VDPAU implementation using VAAPI backend
      ];
    };
  };
  services.xserver.videoDrivers = [ "modesetting" "fbdev" ];
  security.wrappers = {
    intel-gpu-top = {
      owner = "root";
      group = "cfo";
      capabilities = "CAP_PERFMON+pe";
      source = "${pkgs.intel-gpu-tools.out}/bin/intel_gpu_top";
    };
  };
}
