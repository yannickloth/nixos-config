# r8712u: kernel module for the Realtek RTL8712-architecture USB Wi-Fi dongles
# (server-nike has two: 0bda:8172 "RTL8191SU 802.11n WLAN Adapter" and
# 06f8:e031 "Guillemot Hercules HWNUm-300" — both in the driver's device table).
#
# Why out-of-tree: this was the in-tree staging driver drivers/staging/rtl8712
# (Kconfig R8712U, module r8712u) until Linux removed it in the 6.12 merge
# window ("staging: rtl8712: Remove driver using deprecated API wext").
# linux_6_12 — the kernel server-nike is pinned to (hardware/nvidia_ampere.nix)
# — does NOT contain it (verified against the 6.12.117 source: the driver
# directory is gone; last in-tree kernel was 6.11). So no kernel config switch
# can help; the module must come from a package.
#
# Source: ylcwa/r8712u-dkms (tag v1.0.0) — a maintained DKMS continuation that
# preserves exactly that staging source plus kernel-compat patches (the 7.x
# patch is only applied on kernels >= 7.0, so 6.12 builds unpatched, matching
# upstream's tested configuration).
#
# Firmware: the driver uploads rtlwifi/rtl8712u.bin (MODULE_FIRMWARE in
# hal_init.c); that file ships in linux-firmware and is wired into the system
# by hardware/usb-wifi.nix.
{
  lib,
  stdenv,
  fetchFromGitHub,
  kernel,
  kernelModuleMakeFlags,
}:

let
  modDestDir = "$out/lib/modules/${kernel.modDirVersion}/extra";

in
stdenv.mkDerivation {
  pname = "r8712u";
  version = "1.0.0";

  src = fetchFromGitHub {
    owner = "ylcwa";
    repo = "r8712u-dkms";
    rev = "9a41be10afe41517306d7fae6e3d792a2c816c88";
    # fetchFromGitHub in this nixpkgs uses recursive (NAR) hashing of the
    # unpacked source.
    hash = "sha256-EliDoC3FmUCWd97eRsf+qMGGMtYbzEgEYxPGgkbAWHk=";
  };

  hardeningDisable = [ "pic" ];

  nativeBuildInputs = kernel.moduleBuildDependencies;

  # Upstream's dkms.conf runs exactly this invocation. Their linux-7 compat
  # patch is gated on kernel >= 7.0 (PATCH_MATCH "^7\."), so 6.x builds use the
  # preserved source unmodified - do not "simplify" this away.
  buildPhase = ''
    runHook preBuild
    make -C ${kernel.dev}/lib/modules/${kernel.modDirVersion}/build \
      M="$PWD/src/rtl8712" \
      CONFIG_R8712U=m \
      ${lib.concatStringsSep " " kernelModuleMakeFlags}
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p ${modDestDir}
    install -Dm644 src/rtl8712/r8712u.ko ${modDestDir}/r8712u.ko
    xz -f ${modDestDir}/r8712u.ko

    runHook postInstall
  '';

  meta = {
    description = "Realtek RTL8712U/RTL8191SU USB WLAN driver (staging driver continuation)";
    homepage = "https://github.com/ylcwa/r8712u-dkms";
    license = lib.licenses.gpl2Only;
    platforms = lib.platforms.linux;
  };
}
