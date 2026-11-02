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
#   Remaining headroom to the desktop benchmark card's 64.6 tok/s (IQ3_XXS,
#   RTX 5070) is ~1.1x: 0.1.51 measures 56.9 tok/s short-chat decode here
#   (2026-10-25; the ~2.3x note above was against the 0.1.18-era 28.4, and the
#   9x gap the stale pin suggested is long gone).
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
# libnvidia-ml.so.1 (NVML) is shimmed alongside it: serve/telemetry.py dlopens
# it by soname for the Monitor tab, and without it the web app shows the GPU as
# "not readable (NVML)" (the engine itself does not use NVML).
#
# The native-embedding error report (the real cudaError instead of upstream's
# bare "cannot pin N MiB") is upstream as of 0.1.40.3; historically it lived in
# the fork (github.com/yannickloth/forks-Strata). The AVX2 IQ3 codebook gather
# (STRATA_IQ256_GATHER, upstream PR #622) is upstream as of 0.1.40, behind
# per-thread selection (see packages/strata/default.nix). The engine-lifecycle
# API this comment used to mention is upstream as of 0.1.31 (--idle-unload).
# Pinned to Strata 0.2.9 (c62d5e3a), whose engine is 0.1.55: the 0.2 releases
# split the engine from the app/Terminal (separately versioned from now on) and
# bumped the engine to 0.1.46 -> 0.1.47 -> 0.1.48 -> 0.1.50 -> 0.1.51 -> 0.1.55 - Gyro trellis experts on CUDA/HIP/SYCL/
# Metal, GPU roles, the NUMA-split CPU pool, an optional API key. Two engine
# changes matter to this package: the K-quant MMQ prompt kernels moved into
# libstrata_kq.so, which the engine dlopens from its own folder (installed
# beside the binary below; without it those experts take the FP16 prompt path),
# and --parallel is now driven by serve/ rather than by the engine config. Our
# config does not set it, so the calibrated knobs and the bench numbers above
# carry over.
# The short-lived rollback to 0.1.43.1 (a0116b2) was for a 0.1.44.1 decode
# regression that a later controlled A/B on this rig did not reproduce (bench
# note in packages/strata/default.nix, Niko1221/Strata#2441/#2010).
# STRATA_ADAPT_OVERLAP stays opt-in and off: 0.1.43's Linux-CUDA-on default cost
# ~2.7x decode on this host (Niko1221/Strata#2010).
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
  # Host family. CachyOS needs the /usr/lib/libcuda.so.1 RUNPATH shim (its
  # NVIDIA driver is not in the Nix store); NixOS finds the driver at
  # /run/opengl-driver/lib via autoAddDriverRunpath, so the shim is skipped.
  # Passed from packages/strata/home.nix via config.commonHm.isCachyOS.
  isCachyOS ? false,
  strataSrc ? fetchFromGitHub {
    owner = "Niko1221";
    repo = "Strata";
    rev = "c62d5e3a15b40ea51c96aae9e8d36928965f53ab";  # v0.2.9; engine 0.1.55
    hash = "sha256-eFuyhZQQNoskUXGB/RkaPvBslg16PZjCS3c8xyl4oZk=";
  },
  # The engine's own version (CMakeLists.txt's project(VERSION ...)), passed from
  # default.nix. Since Strata 0.2.0 the engine is versioned apart from the app:
  # the v0.2.9 tree builds engine 0.1.55 while the app is 0.2.9 (since 0.2.4 the
  # releases also ship separately versioned engine packages, 0.1.55 in v0.2.9).
  engineVersion ? "0.1.55",
  llamaCpp ? fetchFromGitHub {
    owner = "ggml-org";
    repo = "llama.cpp";
    # Pinned by upstream (third_party/ggml/VERSION.txt).
    rev = "3cf03257f219afbe7334045ff7c6a06ac68c627d";
    hash = "sha256-SRGoXa+4ACBCB3eaG9XFYhMN1i0FyPEy9Rrer+dFGYI=";
  },
}:

let
  meta = with lib; {
    description =
      "Strata inference engine: Qwen3.8-Flash-Next (125B MoE) on a 12 GB NVIDIA GPU + system RAM";
    homepage = "https://github.com/Niko1221/Strata";
    # The repo carries an MIT LICENSE (upstream added it after this package was
    # written; the model weights are a separate matter).
    license = licenses.mit;
    platforms = platforms.linux;
  };

  engine = stdenv.mkDerivation {
    pname = "strata-engine";
    version = engineVersion;
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
    # The K-quant MMQ prompt kernels (Q4_K/Q5_K/Q5_1; ON by default since the
    # 0.2 line, and setup.py passes it explicitly). With it, the UD-Q4_K_XL GGUF
    # experts use int8 tensor cores instead of dequant + cuBLAS; the IQ3_XXS
    # native pack is unaffected. The kernels live in libstrata_kq.so, which the
    # engine dlopens only for a model with those formats (installed below).
    (lib.cmakeBool "STRATA_MMQ_KQUANTS" true)
    # The Q6_K gate/up expert kernels for the UD-Q6_K_XL files. ON upstream;
    # named here so an upstream default change cannot silently change what this
    # package builds (both are in setup.py's own cmake line).
    (lib.cmakeBool "STRATA_Q6K_EXPERTS" true)
    # STRATA_MMQ_TQ_OVERLAY stays at its default (ON): at configure time it
    # writes patched copies of the pinned llama.cpp's ggml-cuda headers into the
    # build tree (never into the read-only store checkout) so the Gyro trellis
    # prompts use MMQ; it disables itself with a message when the pinned
    # llama.cpp is not the one it knows.
    (lib.cmakeFeature "STRATA_GGML_DIR" "${llamaCpp}")
    (lib.cmakeFeature "CMAKE_CUDA_ARCHITECTURES" cudaArch)
    # Experiment 2026-09-27 (see matrix in the header): global --use_fast_math
    # measured 5.5 tok/s vs 6.3 baseline - no gain, reverted.
    # (lib.cmakeFeature "CMAKE_CUDA_FLAGS" "--use_fast_math")
  ];

  installPhase = ''
    runHook preInstall
    install -Dm755 strata $out/bin/strata
    # libstrata_kq.so: the K-quant MMQ prompt kernels (STRATA_MMQ_KQUANTS), a
    # shared library the engine dlopens from ITS OWN folder (/proc/self/exe's
    # dir - $out/bin here) the first time a model asks for Q4_K/Q5_K/Q5_1/Q6_K
    # experts. It is built as a dependency of the `strata` target; without it
    # those experts silently take the FP16 prompt path (the engine says so once).
    if [ -f libstrata_kq.so ]; then
      install -Dm755 libstrata_kq.so $out/bin/libstrata_kq.so
    fi
    runHook postInstall
  '';

  # The NVIDIA driver (libcuda) is a host library: on CachyOS it lives in
  # /usr/lib, which the nix loader does not search, and cudart dlopens it at
  # run time. Expose it through a symlink dir referenced from the binary's
  # RUNPATH (added post-fixup so RPATH shrinking does not strip it) and the
  # wrapper's LD_LIBRARY_PATH. On NixOS the driver is at /run/opengl-driver/lib
  # (autoAddDriverRunpath puts it on the RUNPATH), so the shim is omitted.
  postFixup = ''
    mkdir -p $out/lib-driver
    ${lib.optionalString isCachyOS ''
      ln -sf /usr/lib/libcuda.so.1 $out/lib-driver/libcuda.so.1
      ln -sf /usr/lib/libnvidia-ml.so.1 $out/lib-driver/libnvidia-ml.so.1
    ''}
    patchelf --add-rpath $out/lib-driver $out/bin/strata
    # the K-quant library links CUDA::cuda_driver (the host's libcuda) too
    if [ -f $out/bin/libstrata_kq.so ]; then
      patchelf --add-rpath $out/lib-driver $out/bin/libstrata_kq.so
    fi
  '';

  meta = meta // { mainProgram = "strata"; };
  };

  vision = stdenv.mkDerivation {
    pname = "strata-vision";
    version = engineVersion;
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

    # ggml-cuda links libcuda.so.1 (the host driver) directly; the /usr/lib
    # shim is CachyOS-only (see the engine's postFixup).
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
symlinkJoin {
  name = "strata-${engineVersion}";
  paths = [ engine ] ++ lib.optional withVision vision;
  inherit meta;
}
