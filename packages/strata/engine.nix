# The Strata engine (https://github.com/Niko1221/Strata) - the CUDA C++ core
# that runs Qwen3.8-Flash-Next (125B MoE) split across a 12 GB NVIDIA GPU,
# system RAM and an SSD lookup table. Upstream hard-requires compute
# capability 8.0+ (RTX 30/40/50) and refuses to build for anything older.
#
# MEASURED PERFORMANCE ON LAPTOP-P16 (RTX A3000 12GB Laptop, GA104, sm_86,
# 60-80W, driver 615.71.09 open module, i7-12850HX AVX2-only, 125 GB RAM,
# output generation through the API, thinking off):
#
#   THE ENGINE VERSION DOMINATES EVERYTHING ELSE.  The same model, pack,
#   tokenizer, MTP layer and run config, only the engine swapped (2026-09-28):
#     fork base 0.1.18 (b38c183)     28.4 tok/s decode   (fresh prose, 64K)
#     our earlier pin a9047fd         8.4 tok/s decode   (identical everything)
#   So the "~6 tok/s quant-independent floor" measured before that date was an
#   artifact of the stale pin: upstream had improved the engine ~3.4x by
#   0.1.18.  (0.1.18 also made --prefill auto fit 262K context in 12 GB, which
#   the old engine could not serve.)  The old matrix, kept for the record, was
#   ALL on a9047fd and is superseded:
#     spec 4 baseline ~6.3, spec 2 5.6, global --use_fast_math 5.5 (reverted),
#     expert cache ON ~7.3 but upstream flags that path's output as incorrect.
#   Content swings decode on the SAME engine/config: fresh prose ~23-28 tok/s,
#   echo-heavy text ~39 tok/s (speculation accepts copied tokens) - so any
#   "Nx faster" claim from chat measurements alone is meaningless.
#
#   Unsloth Studio (llama.cpp, generic MoE offload) ran the same GGUFs at
#   ~2 tok/s for the 125B (2026-09-28) - llama.cpp does support the qwen4exp
#   architecture, so that comparison is apples to apples.
#
#   EXPERIMENTAL SPEED PROJECTION (data/experimental-speed-projection/): NOT an
#   optimization - it projects out a refusal direction on layers 4-44.  Upstream
#   measures 0.2-0.4% *slower* on identical tokens; apparent tok/s rises only
#   because the model writes different text (fewer refusals, more echoing).
#   Upstream: "removing refusals removes a safety behaviour".  Off by default;
#   keep it off unless that trade is wanted knowingly.
#
#   Remaining headroom is now ~2.3x to the desktop benchmark card's 64.6 tok/s
#   (IQ3_XXS, RTX 5070) - consistent with 2x bandwidth and a 60-80W laptop
#   part, rather than the 9x gap the stale pin suggested.
#
# Two CUDA builds ship here:
#   strata        - the inference engine (main target)
#   strata-vision - the image encoder (tools/vision; links llama.cpp's mtmd,
#                   ggml-cuda for the GPU path) - only built when withVision
#
# Upstream's CMake would FetchContent a pinned llama.cpp (ggml for the native
# IQ expert kernels, mtmd for the encoder) from inside the build, which the
# Nix sandbox forbids; the STRATA_GGML_DIR / LLAMA_DIR escape hatches point it
# at a fetched llama.cpp instead.
#
# STRATA_PORTABLE=ON keeps ggml reproducible (AVX2 baseline instead of
# -march=native): Strata's own AVX-512 expert kernels are chosen at run time
# either way, and the i7-12850HX has no AVX-512, so nothing is lost here.
#
# lib-driver (postFixup, both binaries): the NVIDIA driver's libcuda.so.1 is
# a host library (/usr/lib on CachyOS), invisible to the nix loader, and
# cudart dlopens it at run time. The symlink dir is referenced from the
# binaries' RUNPATH and the wrappers' LD_LIBRARY_PATH. Without it, the engine
# dies with "native embedding: cannot pin 322 MiB: CUDA driver version is
# insufficient for CUDA runtime version" (the message is misleading - it is
# libcuda resolution, not memory). Pinned allocations otherwise work even
# under RLIMIT_MEMLOCK=8M: the open kernel module does not enforce it.
#
# The native-embedding error report (the real cudaError instead of upstream's
# bare "cannot pin N MiB") and the serve lifecycle API (/api/inference/*,
# --no-preload, --idle-unload) live in the fork (github.com/yannickloth/
# forks-Strata, branch local/lifecycle), not as patches here.
{
  lib,
  stdenv,
  pkgs,
  cudaPackages,
  cmake,
  fetchFromGitHub,
  symlinkJoin,
  cudaArch ? "86", # laptop-p16: RTX A3000 12GB Laptop GPU (compute capability 8.6)
  withVision ? false, # also build the strata-vision image encoder
  strataSrc ? fetchFromGitHub {
    owner = "Niko1221";
    repo = "Strata";
    rev = "a9047fdb79acf9382fa6623a89290327e29235f4";
    hash = "sha256-qeDI9D12WuWs/+6MOIwtWqqeqeWRt4sQ/sEwj/lo6Uk=";
  },
  llamaCpp ? fetchFromGitHub {
    owner = "ggml-org";
    repo = "llama.cpp";
    # Pinned by upstream (third_party/ggml/VERSION.txt).
    rev = "3cf03257f219afbe7334045ff7c6a06ac68c627d";
    hash = "sha256-SRGoXa+4ACBCB3eaG9XFYhMN1i0FyPEy9Rrer+dFGYI=";
  },
}:

let
  version = "0.1.0-unstable-2026-09-27";

  meta = with lib; {
    description =
      "Strata inference engine: Qwen3.8-Flash-Next (125B MoE) on a 12 GB NVIDIA GPU + system RAM";
    homepage = "https://github.com/Niko1221/Strata";
    # Upstream ships no LICENSE file (the README says "free and open source");
    # treated as unfree until one is added.
    license = licenses.unfree;
    platforms = platforms.linux;
  };

  engine = stdenv.mkDerivation {
    pname = "strata-engine";
    inherit version;
    src = strataSrc;

  stdenv = cudaPackages.stdenv;
  nativeBuildInputs = [
    cmake
    cudaPackages.cuda_nvcc
    # Adds /run/opengl-driver/lib to the RPATH so the driver's libcuda is
    # found at run time on NixOS (the hook is called autoAddDriverRunpath in
    # nixpkgs; on CachyOS the driver loads from /usr/lib, see postFixup).
    pkgs.autoAddDriverRunpath
    pkgs.patchelf
  ];
  buildInputs = [
    cudaPackages.cuda_cudart
    cudaPackages.libcublas
  ];

  # Build only the `strata` engine target: with CUDA on, upstream also
  # registers a dozen *_parity test binaries it never installs.
  buildFlags = [ "strata" ];

  cmakeFlags = [
    (lib.cmakeBool "STRATA_ENABLE_CUDA" true)
    (lib.cmakeBool "STRATA_BUILD_TESTS" false)
    (lib.cmakeBool "STRATA_PORTABLE" true)
    (lib.cmakeFeature "STRATA_GGML_DIR" "${llamaCpp}")
    (lib.cmakeFeature "CMAKE_CUDA_ARCHITECTURES" cudaArch)
    # Experiment 2026-09-27 (see matrix in the header): global --use_fast_math
    # measured 5.5 tok/s vs 6.3 baseline - no gain, reverted.
    # (lib.cmakeFeature "CMAKE_CUDA_FLAGS" "--use_fast_math")
  ];

  installPhase = ''
    runHook preInstall
    install -Dm755 strata $out/bin/strata
    runHook postInstall
  '';

  # The NVIDIA driver (libcuda) is a host library: on CachyOS it lives in
  # /usr/lib, which the nix loader does not search, and cudart dlopens it at
  # run time. Expose it through a symlink dir referenced from the binary's
  # RUNPATH (added post-fixup so RPATH shrinking does not strip it) and the
  # wrapper's LD_LIBRARY_PATH. The dir contains only libcuda, so it cannot
  # shadow nix libraries.
  postFixup = ''
    mkdir -p $out/lib-driver
    ln -sf /usr/lib/libcuda.so.1 $out/lib-driver/libcuda.so.1
    patchelf --add-rpath $out/lib-driver $out/bin/strata
  '';

  meta = meta // { mainProgram = "strata"; };
  };

  vision = stdenv.mkDerivation {
    pname = "strata-vision";
    inherit version;
    src = strataSrc;
    sourceRoot = "source/tools/vision";

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
      (lib.cmakeFeature "LLAMA_DIR" "${llamaCpp}")
      (lib.cmakeFeature "CMAKE_CUDA_ARCHITECTURES" cudaArch)
    ];

    # Upstream sets RUNTIME_OUTPUT_DIRECTORY to <build>/bin.
    installPhase = ''
      runHook preInstall
      install -Dm755 bin/strata-vision $out/bin/strata-vision
      runHook postInstall
    '';

    # ggml-cuda links libcuda.so.1 (the host driver) directly; see the
    # engine's postFixup for why the symlink dir is needed on CachyOS.
    postFixup = ''
      mkdir -p $out/lib-driver
      ln -sf /usr/lib/libcuda.so.1 $out/lib-driver/libcuda.so.1
      patchelf --add-rpath $out/lib-driver $out/bin/strata-vision
    '';

    meta = meta // { mainProgram = "strata-vision"; };
  };
in
symlinkJoin {
  name = "strata-${version}";
  paths = [ engine ] ++ lib.optional withVision vision;
  inherit meta;
}
