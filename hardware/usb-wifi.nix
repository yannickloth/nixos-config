# USB Wi-Fi dongles (currently server-nike: two Realtek RTL8191SU/RTL8188SU
# sticks, 0bda:8172 "RTL8191SU 802.11n WLAN Adapter" and 06f8:e031 "Guillemot
# Hercules HWNUm-300" — both are RTL8712-architecture chips, both in the
# driver's device table).
#
# Driver: the in-tree staging driver (drivers/staging/rtl8712, Kconfig
# R8712U, module r8712u) was REMOVED in the 6.12 merge window ("staging:
# rtl8712: Remove driver using deprecated API wext"); the last in-tree kernel
# was 6.11. The pinned linux_6_12 (hardware/nvidia_ampere.nix) does NOT
# contain it — verified against the 6.12.117 source, whose drivers/staging
# has no rtl8712. So no kernel config switch can help; the driver is the
# out-of-tree package packages/r8712u (a maintained continuation of the same
# staging source), wired in via boot.extraModulePackages. Everything else is
# automatic:
#
#   - the module lands in the merged module tree with its usb: modaliases,
#     so udev's modprobe rule loads it on insertion (no extra udev rule);
#   - `boot.kernelModules` also loads it at boot, in case a stick is plugged
#     in before stage-1 udev runs;
#   - the firmware the driver uploads, rtlwifi/rtl8712u.bin, ships in
#     linux-firmware and is added to hardware.firmware explicitly below,
#     because server-nike's import chain does NOT set
#     hardware.enableAllFirmware (only the family laptops do, via
#     environments/family-laptop.nix) and the dongle must not depend on that
#     host-wide policy.
#
# KERNEL UPDATE CONSTRAINT — read before bumping this host's kernel:
#   The dongle driver is out-of-tree and MUST build against whatever kernel
#   the host boots. packages/r8712u is pinned to a source that builds
#   unpatched on 6.x and carries upstream's compat patches for >= 7.0. When
#   the kernel moves on: rebuild `nix build .#r8712u` against the new kernel;
#   if it no longer compiles, update the pinned rev in
#   packages/r8712u/default.nix (upstream tracks kernel changes). If the
#   module is missing, the build fails loudly (boot.kernelModules asserts
#   every module exists) rather than the dongles going dark at runtime.
#   See also the kernel notes in flake.nix (mkHost) and hardware/nvidia_ampere.nix.
{ config, pkgs, ... }:

{
  # The out-of-tree driver, built against the host's actual kernel so it
  # survives any kernelPackages change.
  boot.extraModulePackages = [
    (pkgs.callPackage ../packages/r8712u {
      kernel = config.boot.kernelPackages.kernel;
      kernelModuleMakeFlags = config.boot.kernelPackages.kernelModuleMakeFlags;
    })
  ];

  # Load at boot (and into the initrd); hotplug auto-load comes from the
  # module's usb: modaliases in the merged modules.alias.
  boot.kernelModules = [ "r8712u" ];

  # Firmware for the driver: rtlwifi/rtl8712u.bin, carried by linux-firmware
  # (see the comment at the top of this file for why this is explicit).
  hardware.firmware = [ pkgs.linux-firmware ];
}
