# Strata (https://github.com/Niko1221/Strata) - one-click runtime for running
# Qwen3.8-Flash-Next (125B MoE) locally on laptop-p16's RTX A3000 (12 GB,
# sm_86): OpenAI- and Anthropic-compatible API on localhost, browser chat
# page, terminal chat.
#
# Packaged like ./laya: the CUDA engine is built in the store (see
# ./engine.nix), while the multi-GB model files, the expert pack, the MTP
# draft layer and the Python environment live in a writable runtime directory
# (~/.local/share/strata, override with STRATA_HOME) and are downloaded or
# created on first run - exactly what upstream's setup.py does, minus the
# engine: the engine/BUILD.json marker ("source": "local") tells setup.py the
# engine is already built, so it never fetches a release zip nor apt-gets a
# CUDA toolchain. The engine is linked against nixpkgs' CUDA libraries, so no
# NVIDIA pip wheels are needed either.
#
# Images (the strata-vision encoder) are opt-in via the `vision` argument
# (off by default: the encoder costs ~1.2 GB of VRAM and a few % of speed).
{ lib
, stdenv
  , symlinkJoin
  , writeShellApplication
  , callPackage
  , fetchFromGitHub
  , pkgs
  , python3
  , uv
  , cudaArch ? "86"
  , vision ? false
, strataSrc ? fetchFromGitHub {
    owner = "Niko1221";
    repo = "Strata";
    rev = "a9047fdb79acf9382fa6623a89290327e29235f4";
    hash = "sha256-qeDI9D12WuWs/+6MOIwtWqqeqeWRt4sQ/sEwj/lo6Uk=";
  }
, llamaCpp ? fetchFromGitHub {
    owner = "ggml-org";
    repo = "llama.cpp";
    rev = "3cf03257f219afbe7334045ff7c6a06ac68c627d";
    hash = "sha256-SRGoXa+4ACBCB3eaG9XFYhMN1i0FyPEy9Rrer+dFGYI=";
  }
,
}:

let
  version = "0.1.0-unstable-2026-09-27";

  # VRAM kept free of expert-cache slots so request-time buffers (verify
  # graphs, prompt borrows, vision activations) never OOM; the auto sizer
  # otherwise fills VRAM completely.
  vramReserveMiB = if vision then 2800 else 1800;

  engine = callPackage ./engine.nix {
    inherit strataSrc llamaCpp cudaArch;
    withVision = vision;
  };

  # The Python side of the repo (setup.py, the API server, the packing tools
  # and their static data), kept read-only in the store. chat.py is stdlib
  # only; serve/ and tools/ use exactly the packages setup.py installs into
  # the venv on first run.
  runtime = stdenv.mkDerivation {
    pname = "strata-runtime";
    inherit version;
    src = strataSrc;
    dontBuild = true;
    installPhase = ''
      runHook preInstall
      mkdir -p $out/share/strata
      install -m644 setup.py chat.py $out/share/strata/
      cp -r serve tools data $out/share/strata/
      runHook postInstall
    '';
  };

  share = "${runtime}/share/strata";

  # Shared preamble: where the mutable runtime state lives, plus the loader
  # path for the venv: pip-installed C extensions (numpy, pillow, ...) expect
  # a system libstdc++/libgcc_s, which the nix-store Python does not expose.
  env = ''
    STRATA_HOME="''${STRATA_HOME:-$HOME/.local/share/strata}"
    # Force Python UTF-8 mode regardless of the session locale (pip warns
    # "Detected locale C ... not UTF-8" otherwise, and encoding defaults
    # become locale-dependent).
    export PYTHONUTF8=1
    # Nix's glibc cannot read a host-generated locale archive, so a valid
    # session LANG like en_GB.UTF-8 still falls back to C inside the venv's
    # Python. Point nix binaries at the host archive - on non-NixOS hosts
    # only: NixOS ships its own archive and sets LOCALE_ARCHIVE session-wide.
    if [ -f /usr/lib/locale/locale-archive ] && ! grep -qs '^ID=nixos' /etc/os-release; then
      export LOCALE_ARCHIVE=/usr/lib/locale/locale-archive
    fi
    export LD_LIBRARY_PATH="${engine}/lib-driver:${pkgs.stdenv.cc.cc.lib}/lib:${pkgs.zlib}/lib''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
  '';

  strata = writeShellApplication {
    name = "strata";
    runtimeInputs = [ uv ];
    text =
      env
      + ''
        mkdir -p "$STRATA_HOME"

        # Refresh the program files from the store; runtime state (models/,
        # packs/, mtp/, engine/, strata-*.json, logs) is left alone. cp keeps
        # the store's read-only modes, so make the copies writable again:
        # otherwise the next refresh's rm (and anything else) would hit
        # "Permission denied" on the unwritable dirs/files.
        chmod -R u+rwX "$STRATA_HOME/serve" "$STRATA_HOME/tools" "$STRATA_HOME/data" 2>/dev/null || true
        rm -rf "$STRATA_HOME/serve" "$STRATA_HOME/tools" "$STRATA_HOME/data"
        cp -r ${share}/serve ${share}/tools ${share}/data "$STRATA_HOME/"
        install -m644 ${share}/setup.py ${share}/chat.py "$STRATA_HOME/"
        chmod -R u+rwX "$STRATA_HOME/serve" "$STRATA_HOME/tools" "$STRATA_HOME/data"

        # The pinned llama.cpp (setup.py only reads gguf-py from it): pre-place
        # it so a fresh runtime dir does not download the source zip.
        if [ ! -e "$STRATA_HOME/third_party/llama.cpp" ]; then
          mkdir -p "$STRATA_HOME/third_party"
          ln -s "${llamaCpp}" "$STRATA_HOME/third_party/llama.cpp"
        fi

        # Engine marker: "source": "local" makes setup.py use the store-built
        # engines as-is (no release download, no apt/pip toolchain bootstrap,
        # no NVIDIA pip wheels). The symlinks track store rebuilds.
        mkdir -p "$STRATA_HOME/engine"
        ln -sfn "${engine}/bin/strata" "$STRATA_HOME/engine/strata"
        printf '%s\n' '{"source": "local", "version": "${version}", "archs": [${cudaArch}], "vision": "${if vision then "gpu" else "none"}", "cuda_dirs": []}' \
          > "$STRATA_HOME/engine/BUILD.json"
        ${lib.optionalString vision ''
        ln -sfn "${engine}/bin/strata-vision" "$STRATA_HOME/engine/strata-vision"
        ''}

        # Python environment for serve/server.py and the packing tools
        # (small wheels; the multi-GB model download happens inside setup.py
        # with resume support). --seed adds the pip module setup.py's own
        # install step expects; the venv is only recreated when missing.
        if [ ! -x "$STRATA_HOME/.venv/bin/python" ]; then
          echo "Strata: creating the Python environment..." >&2
          rm -rf "$STRATA_HOME/.venv"
          uv venv --seed --python "${python3}/bin/python3" "$STRATA_HOME/.venv" >&2
        fi

        # The auto expert cache sizes itself to the last MiB of VRAM and
        # leaves too little for request-time buffers - the engine then dies
        # on the first request ("verify: instantiate: out of memory") even
        # though it warns "LOW" at startup. Enforce a healthy VRAM reserve
        # in every config; setup.py only writes 700 MiB (for vision).
        ${python3}/bin/python3 - <<'PY' >&2
        import glob, json, os, sys
        home = os.environ.get("STRATA_HOME") or os.path.expanduser("~/.local/share/strata")
        for p in glob.glob(os.path.join(home, "strata-*.json")):
            try:
                with open(p, encoding="utf-8") as f:
                    c = json.load(f)
                args = c.setdefault("args", [])
                # Upstream warns the expert-cache GPU hit path produces output
                # that diverges from a cache-off run; on this GPU it is also
                # barely faster (6 vs 7.3 tok/s), so keep it off.
                while "--expert-cache" in args:
                    i = args.index("--expert-cache")
                    del args[i:i+2]
                if "--vram-reserve-mib" in args:
                    args[args.index("--vram-reserve-mib") + 1] = "${toString vramReserveMiB}"
                else:
                    args += ["--vram-reserve-mib", "${toString vramReserveMiB}"]
                with open(p, "w", encoding="utf-8") as f:
                    json.dump(c, f, indent=1)
            except Exception as e:
                print(f"strata: could not patch {p}: {e}", file=sys.stderr)
        PY

        # The model wants the A3000's full 12 GB of VRAM and tens of GB of
        # RAM, so free them: stop the Unsloth Studio service when the model
        # is actually about to start (--setup/--check/--no-start don't).
        # Restart it afterwards with: systemctl --user start unsloth-studio
        start_model=1
        for arg in "$@"; do
          case "$arg" in
            --setup | --check | --no-start) start_model=0 ;;
          esac
        done
        if [ "$start_model" = 1 ] && systemctl --user is-active --quiet unsloth-studio 2>/dev/null; then
          echo "Strata: stopping unsloth-studio (frees VRAM/RAM for the model)..." >&2
          systemctl --user stop unsloth-studio
        fi

        cd "$STRATA_HOME"
      ''
      + lib.optionalString vision ''
        # Images on by default when the package ships the vision encoder
        # (~1.2 GB VRAM for the encoder, a few % slower text, ~0.9 GB extra
        # download). Override at setup time with e.g. `strata --vision no`.
        want_vision_explicit=0
        for arg in "$@"; do
          case "$arg" in
            --vision | --vision=*) want_vision_explicit=1 ;;
          esac
        done
        if [ "$want_vision_explicit" = 0 ]; then
          set -- "$@" --vision yes
        fi
      ''
      + ''
        exec "$STRATA_HOME/.venv/bin/python" setup.py "$@"
      '';
  };

  # Terminal chat against a running Strata server (start it with `strata`).
  strata-chat = writeShellApplication {
    name = "strata-chat";
    text =
      env
      + ''
        if [ ! -x "$STRATA_HOME/.venv/bin/python" ]; then
          echo "Strata: not set up yet - run 'strata' first (it installs everything and starts the model)." >&2
          exit 1
        fi
        cd "$STRATA_HOME"
        exec "$STRATA_HOME/.venv/bin/python" chat.py "$@"
      '';
  };
in
symlinkJoin {
  name = "strata-${version}";
  paths = [
    runtime
    strata
    strata-chat
  ];
  meta = with lib; {
    description = "Strata: local Qwen3.8-Flash-Next (125B MoE) inference with an OpenAI/Anthropic-compatible API";
    homepage = "https://github.com/Niko1221/Strata";
    license = licenses.unfree; # no LICENSE file upstream (see ./engine.nix)
    platforms = platforms.linux;
    mainProgram = "strata";
  };
}
