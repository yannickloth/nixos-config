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
  dollar = "$";

  # Engine derivation: unpacks the tarball directly and copies the Kintsugi-27B
  # directory into the store with the model file and driver libraries.
  engine = stdenv.mkDerivation {
    pname = "kintsugi-27b-engine";
    inherit version;
    src = fetchurl {
      url = "https://github.com/professorpalmer/Kintsugi-27B/releases/download/v${version}/Kintsugi-27B-v${version}-linux-x86_64.tar.gz";
      sha256 = "sha256:0d55dd1bc0e943276208ea8343e95d93a42b3f5a025c11c7000c9d95e092d701";
    };
    nativeBuildInputs = [ pkgs.autoAddDriverRunpath ];
    dontBuild = true;
    # stdenv's single-directory heuristic sets sourceRoot=Kintsugi-27B and
    # renames that directory to $PWD during unpack.  So the contents of
    # Kintsugi-27B/ are at $PWD/ after unpack.  We wrap them into the same
    # directory structure the runtime expects ($out/Kintsugi-27B/*).
    installPhase = ''
      runHook preInstall
      mkdir -p $out/Kintsugi-27B
      cp -r ./* $out/Kintsugi-27B/
      cp ${fetchurl {
        url = "https://huggingface.co/CaryPalmer/Kintsugi-27B/resolve/main/Kintsugi-27B-12G.gguf";
        sha256 = "sha256:0510bae82445dc53dbc7d0d842d8b7e146b8eafce0837e39b157d411e48c8a74";
      }} $out/Kintsugi-27B/models/Kintsugi-27B-12G.gguf

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
  # NVIDIA driver libs), reads KINTSUGI_PORT from the environment, and starts
  # the engine with --port and --wait.
  wrapper = writeShellApplication {
    name = "kintsugi-27b";
    runtimeInputs = [ coreutils pkgs.bash ];
    text = ''
      runtime="$HOME/.local/share/kintsugi-27b"
      engineDir="$runtime/Kintsugi-27B"

      # Copy the engine to the runtime directory so start-server.sh's
      # ROOT variable resolves to a writable location (the Nix store is
      # read-only and the script writes logs/PID files there).
      if [ ! -d "$engineDir" ]; then
        cp -r ${engine}/Kintsugi-27B "$engineDir"
      fi

      # Symlink the model from the store into the runtime copy.
      model="$engineDir/models/Kintsugi-27B-12G.gguf"
      want="${engine}/Kintsugi-27B/models/Kintsugi-27B-12G.gguf"
      if [ ! -e "$model" ] || [ "$(readlink -f "$model" 2>/dev/null)" != "$want" ]; then
        ln -sf "$want" "$model"
      fi

      # Use the runtime copy's lib-driver symlinks (the store copy has
      # none on NixOS, only on CachyOS where /usr/lib is always available).
      mkdir -p "$engineDir/lib-driver"
      if [ -f /usr/lib/libcuda.so.1 ]; then
        ln -sf /usr/lib/libcuda.so.1 "$engineDir/lib-driver/libcuda.so.1"
        ln -sf /usr/lib/libnvidia-ml.so.1 "$engineDir/lib-driver/libnvidia-ml.so.1"
      fi

      export LD_LIBRARY_PATH="$engineDir/bin:$engineDir/lib-driver:''${LD_LIBRARY_PATH:-}"

      cd "$engineDir"
      PORT=${dollar}{KINTSUGI_PORT:-9931}
      exec start-server.sh --port "$PORT" --wait
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
