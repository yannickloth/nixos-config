# Shared NVIDIA configuration for the Ampere hosts: server-nike (RTX 3060 12GB)
# and laptop-p16 (RTX A3000 12GB).
#
# One rule: the kernel and the driver come from ONE nixpkgs evaluation.
# `linux_6_12` is the newest kernel in the pinned stable nixpkgs that still has
# an `nvidia_x11` built against it. Taking the kernel from the unstable set and
# the driver from the stable set produced, on server-nike,
# "API mismatch: the client nvidia-ctk" and
# "Failed to initialize NVML: Driver/Library version mismatch".
#
# The proprietary modules are used on both hosts. On these cards the open
# modules spin kwin_wayland and kmscon on their KMS/DRM paths.
{
  config,
  lib,
  pkgs,
  ...
}:

{
  # nixpkgs gates the entire NVIDIA module on this list:
  # `nixos/modules/hardware/video/nvidia.nix` computes
  # `nvidiaEnabled = elem "nvidia" config.services.xserver.videoDrivers` and puts
  # the Xorg driver, the nvidia-drm KMS setup and the container-toolkit
  # assertion behind it. The option default is [ "modesetting" "fbdev" ], which
  # matches an Intel iGPU. Without "nvidia" the driver package is installed but
  # never wired into the display stack, so no compositor gets a KMS device.
  services.xserver.videoDrivers = [ "nvidia" ];

  # mkForce: flake.nix gives every host a default kernelPackages in mkHost.
  boot.kernelPackages = lib.mkForce pkgs.linuxKernel.packages.linux_6_12;

  hardware.nvidia = {
    # The driver built against this exact kernel, from the same evaluation.
    package = config.boot.kernelPackages.nvidia_x11;
    open = false;
  };
}
