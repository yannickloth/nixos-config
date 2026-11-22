# Kintsugi-27B v1.1.1 — NixOS + CachyOS packaging.
#
# A pre-built GGUF inference engine (Qwen3.8-27B at 2.47 bits per weight) that
# runs on one 12 GB NVIDIA card with a full 262,144-token context. Apache-2.0.
#
# The bundle ships its own CUDA 12.8 runtime, cuBLAS, and the OpenMP runtime
# (libgomp) in bin/. It needs libcuda.so.1 from the NVIDIA driver at runtime.
# The engine is a llama.cpp fork with EXL3 trellis kernels; stock llama.cpp,
# Ollama, and LM Studio cannot load the model.
#
# NVIDIA driver resolution follows the Strata pattern:
# - NixOS: autoAddDriverRunpath injects the driver's rpath into the engine
# - CachyOS: lib-driver/ symlinks to /usr/lib/libcuda.so.1 (distro driver)
#
# Runtime: copies the model file into ~/.local/share/kintsugi-27b/models/ and
# runs start-server.sh from that directory, so the engine finds the model at
# the same relative path the bundle expects. The service uses ai.slice resource
# budget and starts at login.

{
  lib,
  stdenv,
  symlinkJoin,
  fetchurl,
  coreutils,
  writeShellApplication,
  pkgs,
  isCachyOS ? false,
}:

let
  version = "1.1.1";
  bundleUrl = "https://github.com/professorpalmer/Kintsugi-27B/releases/download/v${version}/Kintsugi-27B-v${version}-linux-x86_64.tar.gz";
  bundleHash = "sha256:0d55dd1bc0e943276208ea8343e95d93a42b3f5a025c11c7000c9d95e092d701";
  modelUrl = "https://huggingface.co/CaryPalmer/Kintsugi-27B/resolve/main/Kintsugi-27B-12G.gguf";
  modelHash = "sha256:0510bae82445dc53dbc7d0d842d8b7e146b8eafce0837e39b157d411e48c8a74";

  # Engine derivation: unpacks the tarball directly and copies the Kintsugi-27B
  # directory into the store with the model file and driver libraries.
  modelFile = fetchurl {
    inherit modelUrl modelHash;
  };

  engine = stdenv.mkDerivation {
    pname = "kintsugi-27b-engine";
    inherit version;
    src = fetchurl {
      inherit bundleUrl bundleHash;
    };
    nativeBuildInputs = [ pkgs.autoAddDriverRunpath ];
    dontBuild = true;
    installPhase = ''
      runHook preInstall
      mkdir -p $out
      cp -r Kintsugi-27B $out/
      cp ${modelFile} $out/Kintsugi-27B/models/Kintsugi-27B-12G.gguf

      # NVIDIA driver libraries for runtime resolution of libcuda.so.1.
      # The engine binary (bin/llama-server) dlopen's it at startup.
      mkdir -p $out/Kintsugi-27B/lib-driver
      ${lib.optionalString isCachyOS ''
        # CachyOS: the NVIDIA driver is installed by the distro into /usr/lib.
        # Create symlinks so the engine finds libcuda.so.1 at runtime via
        # the rpath we patch below.
        ln -sf /usr/lib/libcuda.so.1 $out/Kintsugi-27B/lib-driver/libcuda.so.1
        ln -sf /usr/lib/libnvidia-ml.so.1 $out/Kintsugi-27B/lib-driver/libnvidia-ml.so.1
      ''}
      runHook postInstall
    '';
  };

  # Runtime wrapper: sets LD_LIBRARY_PATH (engine's bundled CUDA runtime +
  # NVIDIA driver libs) and starts the engine in --wait mode.
  wrapper = writeShellApplication {
    name = "kintsugi-27b";
    runtimeInputs = [ coreutils pkgs.bash ];
    text = ''
      export LD_LIBRARY_PATH="${engine}/Kintsugi-27B/bin:${engine}/Kintsugi-27B/lib-driver:''${LD_LIBRARY_PATH:-}"

      runtime="$HOME/.local/share/kintsugi-27b"
      mkdir -p "$runtime/models"

      # Symlink the model from the store into the runtime directory.
      model="$runtime/models/Kintsugi-27B-12G.gguf"
      want="${engine}/Kintsugi-27B/models/Kintsugi-27B-12G.gguf"
      if [ ! -e "$model" ] || [ "$(readlink -f "$model" 2>/dev/null)" != "$want" ]; then
        ln -sf "$want" "$model"
      fi

      cd "$runtime"
      exec ${engine}/Kintsugi-27B/start-server.sh --wait
    '';
  };

in
symlinkJoin {
  name = "kintsugi-27b-${version}";
  paths = [ engine wrapper ];
  passthru = {
    runtimeDir = "$HOME/.local/share/kintsugi-27b";
    modelPath = "${engine}/Kintsugi-27B/models/Kintsugi-27B-12G.gguf";
  };
  meta = with lib; {
    description = "Kintsugi-27B: Qwen3.8-27B at 2.47 bits for 12 GB NVIDIA cards, 262k context";
    homepage = "https://github.com/professorpalmer/Kintsugi-27B";
    license = licenses.asl20;
    platforms = platforms.linux;
    mainProgram = "kintsugi-27b";
  };
}
