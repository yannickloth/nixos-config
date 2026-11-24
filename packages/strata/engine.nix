# Strata engine 0.1.67 for Strata 0.2.21 — CUDA 12.9, sm_86 (RTX A3000, RTX 3060).
#
# Upstream 0.2.16 restructured the repo: engine/ is now a separate top-level
# directory with a vendored ggml (third_party/strata-ggml). No more FetchContent
# llama.cpp, no STRATA_GGML_DIR, no libstrata_kq.so (MMQ prompt kernels left
# the tree). The vision encoder moved to terminal/tools/vision and uses Strata's
# own vision tower — no llama.cpp/mtmd/ggml linkage.
#
# This build mirrors upstream's `tools/packaging/build_cuda_linux.sh`
# (cuda12 lane): STRATA_PORTABLE=ON (AVX2 baseline), STRATA_Q6K_EXPERTS=ON,
# tests disabled, archs sm_86-real;86-virtual. The engine links against
# nixpkgs' CUDA libraries so no NVIDIA pip wheels are needed.
#
# lib-driver (postFixup, both binaries): the NVIDIA driver's libcuda.so.1 is a
# host library, invisible to the nix loader; cudart dlopens it at run time.
# autoAddDriverRunpath puts /run/opengl-driver/lib on the RUNPATH; CachyOS
# uses the /usr/lib shim (isCachyOS flag, same as the old design).

{
  lib,
  stdenv,
  pkgs,
  cudaPackages,
  cmake,
  fetchFromGitHub,
  cudaArch ? "86", # both inference hosts are compute capability 8.6: RTX A3000 Laptop (laptop-p16), RTX 3060 (server-nike)
  withVision ? false,
  isCachyOS ? false,
  strataSrc ? fetchFromGitHub {
    owner = "Niko1221";
    repo = "Strata";
    rev = "v0.2.21";  # Engine 0.1.67, feed 130
    hash = "sha256-AhmGZPvxkBqFGsA2CDxiaiW1CwncjOuZESJX1G2Xv0A=";
  },
  engineVersion ? "0.1.67",
}:

let
  meta = with lib; {
    description = "Strata inference engine: Qwen3.8-Flash-Next (125B MoE) on a 12 GB NVIDIA GPU + system RAM";
    homepage = "https://github.com/Niko1221/Strata";
    license = licenses.mit;
    platforms = platforms.linux;
  };
in

let
  # --- Engine (strata binary) ---
  engine = stdenv.mkDerivation {
    pname = "strata-engine";
    version = engineVersion;
    src = strataSrc;
    sourceRoot = "source/engine";

    stdenv = cudaPackages.stdenv;
    nativeBuildInputs = [
      cmake
      cudaPackages.cuda_nvcc
      pkgs.autoAddDriverRunpath
      pkgs.patchelf
    ];
    buildInputs = [
      cudaPackages.cuda_cudart
      cudaPackages.libcublas
    ];

    buildFlags = [ "strata" ];

    cmakeFlags = [
      (lib.cmakeBool "STRATA_ENABLE_CUDA" true)
      (lib.cmakeBool "STRATA_BUILD_TESTS" false)
      (lib.cmakeBool "STRATA_NATIVE_EXPERTS" true)
      (lib.cmakeBool "STRATA_PORTABLE" true)
      (lib.cmakeBool "STRATA_Q6K_EXPERTS" true)
      (lib.cmakeFeature "CMAKE_CUDA_ARCHITECTURES" "${cudaArch}-real;${cudaArch}-virtual")
    ];

    installPhase = ''
      runHook preInstall
      install -Dm755 strata $out/bin/strata
      # libstrata_kq.so left the tree in 0.2.16; nothing to install here.
      runHook postInstall
    '';

    postFixup = ''
      mkdir -p $out/lib-driver
      ${lib.optionalString isCachyOS ''
        ln -sf /usr/lib/libcuda.so.1 $out/lib-driver/libcuda.so.1
        ln -sf /usr/lib/libnvidia-ml.so.1 $out/lib-driver/libnvidia-ml.so.1
      ''}
      patchelf --add-rpath $out/lib-driver $out/bin/strata
    '';

    meta = meta // { mainProgram = "strata"; };
  };

  # --- Vision encoder (strata-vision binary) ---
  # Since 0.2.16: Strata's own Qwen vision tower (terminal/tools/vision/own).
  # No llama.cpp, no mtmd, no ggml linkage. Compiled with same archs as engine.
  vision = stdenv.mkDerivation {
    pname = "strata-vision";
    version = engineVersion;
    src = strataSrc;
    sourceRoot = "source/terminal/tools/vision";

    stdenv = cudaPackages.stdenv;
    nativeBuildInputs = [
      cmake
      cudaPackages.cuda_nvcc
      pkgs.autoAddDriverRunpath
      pkgs.patchelf
    ];
    buildInputs = [
      cudaPackages.cuda_cudart
      cudaPackages.libcublas
    ];

    buildFlags = [ "strata-vision" ];

    cmakeFlags = [
      (lib.cmakeBool "STRATA_VISION_CUDA" true)
      (lib.cmakeBool "STRATA_PORTABLE" true)
      (lib.cmakeFeature "CMAKE_CUDA_ARCHITECTURES" "${cudaArch}-real;${cudaArch}-virtual")
    ];

    # Upstream sets RUNTIME_OUTPUT_DIRECTORY to <build>/bin.
    installPhase = ''
      runHook preInstall
      install -Dm755 bin/strata-vision $out/bin/strata-vision
      runHook postInstall
    '';

    postFixup = ''
      mkdir -p $out/lib-driver
      ${lib.optionalString isCachyOS ''
        ln -sf /usr/lib/libcuda.so.1 $out/lib-driver/libcuda.so.1
        ln -sf /usr/lib/libnvidia-ml.so.1 $out/lib-driver/libnvidia-ml.so.1
      ''}
      patchelf --add-rpath $out/lib-driver $out/bin/strata-vision
    '';

    meta = meta // { mainProgram = "strata-vision"; };
  };

in
pkgs.symlinkJoin {
  name = "strata-${engineVersion}";
  paths = [ engine ] ++ lib.optional withVision vision;
  inherit meta;
}
