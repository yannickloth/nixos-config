# Strata 0.2.17 — NixOS packaging.
#
# Upstream 0.2.16 restructured the repo (Terminal → terminal/, Engine → engine/),
# and 0.2.17 ships the engine as a versioned "component" with a per-file SHA-256
# manifest (engine-component.json). Both `strata launch` (Terminal) and the
# desktop app install models through setup.py in CONTROL mode, writing
# `exe: "component:strata-engine"`.
#
# This package ships a Nix-built engine as an engine component, and the Terminal
# tree (including setup.py, strata.py, serve/, strata_cli/, strata_control/,
# tools/, data/, requirements*.txt) as the read-only program source. The runtime
# directory (`$STRATA_HOME` = `~/.local/share/strata`, override with
# `STRATA_HOME`) is refreshed from the store on every `strata` invocation and
# on every `strata-server` start (the latter covers `home-manager switch`
# service restarts). Everything mutable (models, packs, run configs, venv, logs)
# lives in the runtime directory, untouched by Nix.
#
# Since Strata 0.2.0 the tree holds three separately versioned products: the
# engine (0.1.63), the Terminal (0.2.17, `strata.py` + `strata_cli`), and the
# desktop app (0.2.17). The engine is versioned apart from the app. The desktop
# AppImage is packaged separately (desktop.nix) and version-locked to the
# Terminal in the flake declaration (home.nix).
#
# Images (the strata-vision encoder) are two separate choices. `visionEncoder`
# says whether the package BUILDS and ships the encoder; `vision` says whether
# setup and strata-server default to using it. Off by default, and flake.nix
# builds the attribute without them. Shipping the encoder costs only disk
# (~1.2 GB of VRAM and a few % of text speed are paid when it is used, plus
# ~0.9 GB of mmproj weights that setup downloads); with it shipped and `vision`
# false, `strata --setup` asks and either answer works. See home.nix.
#
# Runtime notes (laptop-p16, established 2026-09-27):
# - The wrapper and `strata-server` run configPatch.py on every engine start.
#   Nix no longer enforces a declarative engine policy: --max-context, --kv,
#   --kv-resident, --rope-scaling, --vram-reserve-mib, --pcie-frac,
#   --spec-min-p, --pool-workers, --adapt-every — all left to `strata --setup`
#   at runtime. The only flag enforced is --expert-cache (native packs refuse
#   to serve without it).
# - Since 0.2.0 a run config carries TWO option lists: "args" (what setup or the
#   app generated) and "user_args" (options the person set by hand, which
#   serve/server.py merges over "args" at every start); "args_written" records
#   what setup last wrote so a later setup run can tell the hand edits apart.
#   The configPatch below therefore writes the policy into "args", takes the
#   policy flags out of "user_args" (the layer that would otherwise win) and
#   re-stamps "args_written" - without that, a value left in the app's settings
#   form would override the module options.
# - Native (IQ) packs REQUIRE --spec >= 2: the engine refuses to start
#   without it, and deeper is faster (spec 4 > spec 2).
# - The engine only resolves libcuda through the wrapper's LD_LIBRARY_PATH
#   (the lib-driver dir, see engine.nix): launching serve/server.py by hand
#   without it fails with a misleading "cannot pin N MiB: CUDA driver
#   version is insufficient".
# - 0.2.17: route-tail-skip is OFF by default (upstream Control sets
#   STRATA_ROUTE_TAIL_SKIP=0 per start). Setup leaves 17 GB of RAM free,
#   not 24 (the 125B is fully resident on 125 GB RAM regardless).
# - Component model: the engine is an installed component (~/.local/share/strata/
#   components/engine/<version>-<platform>-<backend>/) with a per-file manifest.
#   `strata launch` writes `exe: "component:strata-engine"`. The store engine
#   is installed into that folder by the wrapper (on every invocation) and by
#   strata-server (on every service start, covering `home-manager switch`).
#   The manifest (engine-component.json) is generated natively in the build.

{
  lib,
  stdenv,
  symlinkJoin,
  writeShellApplication,
  callPackage,
  fetchFromGitHub,
  pkgs,
  python3,
  uv,
  util-linux,
  coreutils,
  cudaArch ? "86",
  vision ? false,
  visionEncoder ? vision,
  isCachyOS ? false,
  context ? null,
  strataSrc ? fetchFromGitHub {
    owner = "Niko1221";
    repo = "Strata";
    rev = "v0.2.17";  # App and Terminal 0.2.17, Control 0.1.62; engine 0.1.63
    hash = "sha256:1cf9fsyzq3mzdp4kqrpm9inrxg8xg2pn3d1yllhxlci56487r99z";
  },
}:

let
  version = "0.2.17";
  engineVersion = "0.1.63";
  visionMarker = if visionEncoder then (if vision then "gpu" else "cpu") else "none";
  dollarBrace = "$" + "{";  # literal "${" to avoid Nix interpolation in bash vars
  helpers = import ../../lib;
  optArg = helpers.optArg;

  # Config patch: run on every engine start to ensure --expert-cache is present
  # and a stale "vision" block cannot survive in a build without the encoder.
  # Also does one-time, idempotent migration of existing run configs from
  # path-based `exe` to `component:strata-engine` (the component model of
  # 0.2.16+). This is the enforcement point of the module policy.
  configPatch = writeShellApplication {
    name = "strata-patch-config";
    runtimeInputs = [ python3 ];
    text = ''
      python3 - ${share} ${lib.boolToString visionEncoder} <<'PY'
      ${builtins.readFile ./config_patch.py}
      PY
    '';
  };

  engine = callPackage ./engine.nix {
    strataSrc = strataSrc;
    inherit engineVersion isCachyOS;
    withVision = visionEncoder;
  };

  engineBin = "${engine}/bin/strata";
  engineVisionBin = if visionEncoder then "${engine}/bin/strata-vision" else null;

  # Runtime derivation: the Terminal tree as it is copied into STRATA_HOME.
  # This is the same layout upstream ships in the Terminal archive — a copy
  # of `terminal/` — kept read-only in the store. The runtime directory is
  # refreshed from the store on every `strata` invocation (see wrapper below).
  runtime = stdenv.mkDerivation {
    pname = "strata-runtime";
    inherit version;
    src = strataSrc;
    dontBuild = true;
    installPhase = ''
      runHook preInstall
      mkdir -p $out/share/strata
      cp -r terminal/* $out/share/strata/
      install -m644 terminal/VERSION $out/share/strata/ 2>/dev/null || true
      runHook postInstall
    '';
  };

  share = "${runtime}/share/strata";

  # Environment preamble: same as before but without the now-unnecessary
  # `third_party/llama.cpp` symlink (setup uses its own GGUF tools).
  # Uses $+{ to produce literal ${ in bash (avoiding Nix interpolation).
  env = ''
    STRATA_HOME="${dollarBrace}STRATA_HOME:-$HOME/.local/share/strata"
    export PYTHONUTF8=1
    if [ -f /usr/lib/locale/locale-archive ] && ! grep -qs '^ID=nixos' /etc/os-release; then
      export LOCALE_ARCHIVE=/usr/lib/locale/locale-archive
    fi
    export LD_LIBRARY_PATH="${engine}/lib-driver:${pkgs.stdenv.cc.cc.lib}/lib:${pkgs.zlib}/lib${dollarBrace}LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH"
    if [ -e /run/opengl-driver/lib/libcuda.so.1 ]; then
      export LD_LIBRARY_PATH="/run/opengl-driver/lib:$LD_LIBRARY_PATH"
    fi
    export STRATA_IQ256_GATHER="${dollarBrace}STRATA_IQ256_GATHER:-1"
  '';

  # --- Component ---
  # The engine installed as an upstream engine component (~/.local/share/strata/
  # components/engine/<version>-linux-x86_64-cuda/). The component carries:
  #   - strata: the wrapper script (configPatch re-asserts --expert-cache on
  #     every start, closing the web-UI-settings-save-restart hole)
  #   - strata-bin: the raw ELF (what the component manifest hashes)
  #   - strata-vision: the image encoder (when visionEncoder is true)
  #   - BUILD.json: version, archs, vision_archs, source metadata
  #   - engine-component.json: per-file SHA-256 manifest
  #
  # The manifest is generated natively (same format as upstream's
  # package_engine.py: every file's SHA-256 and size, arch list, build id,
  # empty signature for unsigned local builds).
  component = pkgs.runCommand "strata-component-${engineVersion}" {
    nativeBuildInputs = [ pkgs.python3 ];
    buildInputs = [ engine ];
  } ''
    dest=$out/${engineVersion}-linux-x86_64-cuda
    mkdir -p $dest

    # The wrapper: configPatch re-asserts --expert-cache on every start.
    # This is the ONLY non-ELF file in the component, and it must be hashed
    # like everything else by the component manifest.
    cat > $dest/strata <<'WRAPPER'
    #!/bin/sh
    exec ${configPatch}/bin/strata-patch-config
    exec "${engineBin}" "$@"
    WRAPPER
    chmod +x $dest/strata

    # Raw engine binary
    cp -a "${engineBin}" $dest/strata-bin

    # Vision encoder (when built)
    ${lib.optionalString visionEncoder ''
    cp -a "${engineVisionBin}" $dest/strata-vision
    ''}

    # BUILD.json — upstream's setup.py reads this for source_version() and
    # stale_binary() checks (both of which fall through for component refs).
    python3 - "$dest" "${engineVersion}" "${cudaArch}" \
      "${if visionEncoder then "true" else "false"}" \
      "${if visionEncoder then visionMarker else ""}" <<'BUILDJSON'
    import json, sys
    dest = sys.argv[1]
    meta = {
        "version": sys.argv[2],
        "source": "local",
        "archs": ["sm_" + sys.argv[3]],
        "cuda_dirs": []
    }
    if sys.argv[4] == "true":
        meta["vision"] = sys.argv[5]
        meta["vision_archs"] = ["sm_" + sys.argv[3]]
    json.dump(meta, open(dest + "/BUILD.json", "w"), indent=1)
    BUILDJSON

    # Generate engine-component.json manifest (SHA-256 per file).
    python3 - "$dest" "${engineVersion}" "${version}" "${cudaArch}" \
      "${if visionEncoder then "true" else "false"}" \
      "${if visionEncoder then visionMarker else ""}" <<'PYEOF'
    import hashlib, json, os, sys
    dest = sys.argv[1]
    engineVersion, version, cudaArch = sys.argv[2], sys.argv[3], sys.argv[4]
    visionEncoder = sys.argv[5] == "true"
    visionMarker = sys.argv[6]
    files = {}
    for name in sorted(os.listdir(dest)):
        p = os.path.join(dest, name)
        if not os.path.isfile(p):
            continue
        with open(p, 'rb') as f:
            data = f.read()
        files[name] = {"sha256": hashlib.sha256(data).hexdigest(), "size": len(data)}
    manifest = {
        "files": files,
        "archs": ["sm_" + cudaArch],
        "min_driver": "nvidia=575.51",
        "build_id": "nix-v" + version + "-cuda12.9",
        "version": engineVersion,
        "platform": "linux-x86_64",
        "signature": ""
    }
    if visionEncoder:
        manifest["vision"] = visionMarker
    json.dump(manifest, open(os.path.join(dest, 'engine-component.json'), 'w'), indent=1)
    PYEOF
  '';

  # --- The `strata` wrapper ---
  # Entry point for `strata`, `strata-chat`, and systemd `strata-server`.
  # Responsibilities:
  #   1. Ensure $STRATA_HOME exists and has the runtime tree (from store).
  #   2. Refresh the engine component from the store.
  #   3. Create the venv if missing; install monitor-req + req.txt stamps.
  #   4. Run configPatch (ensures --expert-cache).
  #   5. Route to strata.py (Terminal CLI).
  strata = writeShellApplication {
    name = "strata";
    runtimeInputs = [ uv util-linux coreutils ];
    text = env
      + ''
        mkdir -p "$STRATA_HOME"

        # One writer at a time for the runtime tree + component.
        exec 9>"$STRATA_HOME/.runtime.lock"
        flock 9

        # Refresh the program files from the store:
        for d in tools data serve strata_cli strata_control; do
          chmod -R u+rwX "$STRATA_HOME/$d" 2>/dev/null || true
          rm -rf "$STRATA_HOME/$d"
          cp -r "${share}/$d" "$STRATA_HOME/"
          chmod -R u+rwX "$STRATA_HOME/$d"
        done
        for f in setup.py strata.py requirements.txt requirements-monitor.txt requirements-nvfp4-local.txt; do
          install -m644 ${share}/$f "$STRATA_HOME/" 2>/dev/null || true
        done

        # Install/refresh the engine component from the store.
        rm -rf "$STRATA_HOME/components"
        cp -r "${component}" "$STRATA_HOME/components/engine"

        # Legacy engine directory cleanup: if the old `engine/` dir exists
        # and contains only legacy files (strata symlink, BUILD.json, no model
        # data), remove it to prevent upstream's engine_src() detection from
        # mistaking the runtime root for a source checkout.
        if [ -d "$STRATA_HOME/engine" ] && ! find "$STRATA_HOME/engine" -name "*.gguf" -o -name "*.bin" -o -name "*.gguf" 2>/dev/null | grep -q .; then
          rm -rf "$STRATA_HOME/engine"
        fi

        # Remove stale CMakeLists.txt from the runtime root if present
        # (left over from 0.2.15-era runtime trees).
        rm -f "$STRATA_HOME/CMakeLists.txt"

        # Python environment for serve/server.py and the packing tools.
        if [ ! -x "$STRATA_HOME/.venv/bin/python" ]; then
          echo "Strata: creating the Python environment..." >&2
          rm -rf "$STRATA_HOME/.venv"
          uv venv --seed --python "${python3}/bin/python3" "$STRATA_HOME/.venv" >&2
        fi

        # Monitor requirements (TUI packages: textual/rich).
        monitor_req="$STRATA_HOME/requirements-monitor.txt"
        monitor_stamp="$STRATA_HOME/.venv/.monitor-requirements"
        if [ -f "$monitor_req" ]; then
          want_sum=$(sha256sum "$monitor_req" | cut -d' ' -f1)
          have_sum=$(cat "$monitor_stamp" 2>/dev/null || true)
          if [ "$want_sum" != "$have_sum" ]; then
            echo "Strata: installing the terminal UI packages..." >&2
            if uv pip install --python "$STRATA_HOME/.venv/bin/python" -r "$monitor_req" >&2; then
              printf '%s\n' "$want_sum" > "$monitor_stamp"
            else
              echo "Strata: the terminal UI packages could not be installed (offline?)" >&2
            fi
          fi
        fi

        # Runtime requirements stamp: ensures pinned packages stay current
        # after `home-manager switch`. CONTROL-mode installs never run pip,
        # so the stamp is the only upgrade path.
        req_stamp="$STRATA_HOME/.venv/.requirements"
        if [ -f "$STRATA_HOME/requirements.txt" ]; then
          want_sum=$(sha256sum "$STRATA_HOME/requirements.txt" | cut -d' ' -f1)
          have_sum=$(cat "$req_stamp" 2>/dev/null || true)
          if [ "$want_sum" != "$have_sum" ]; then
            echo "Strata: updating runtime packages..." >&2
            if uv pip install --python "$STRATA_HOME/.venv/bin/python" -r "$STRATA_HOME/requirements.txt" >&2; then
              printf '%s\n' "$want_sum" > "$req_stamp"
            else
              echo "Strata: runtime packages could not be updated (offline?)" >&2
            fi
          fi
        fi

        # Everything that needed a consistent runtime tree is done.
        flock -u 9

        # Ensure --expert-cache on every run (native packs refuse without it).
        ${configPatch}/bin/strata-patch-config

        # Route to strata.py (the Terminal CLI).
        # Legacy flags map to `launch`: bare `strata` = `launch`,
        # --setup = removed (launch is the default), --vision yes/no = on/off,
        # --context <int> passes through.
        case "''${1:-}" in
          --version | -V | serve | profile | repair-access | doctor | components | update | \
          models | drafting | engine | install | runtime | ops | bench | timeskip | tune | \
          presets | connect | status | monitor | logs | connection | config | code)
            exec "$STRATA_HOME/.venv/bin/python" "$STRATA_HOME/strata.py" "$@"
            ;;
          split)
            exec "$STRATA_HOME/.venv/bin/python" "$STRATA_HOME/strata.py" "$@"
            ;;
        esac

        # Legacy mapping: bare `strata` = `launch`. Transform --vision yes/no -> on/off,
        # pass through other flags. Build a space-separated arg string to avoid
        # bash array interpolation (which Nix would try to parse).
        launch_args=""
        for arg in "$@"; do
          case "$arg" in
            --setup|"-s") ;;  # no-op — launch is default
            --vision=yes) launch_args="$launch_args --vision on" ;;
            --vision=no) launch_args="$launch_args --vision off" ;;
            --vision=*) launch_args="$launch_args $arg" ;;
            --context=*) launch_args="$launch_args $arg" ;;
            --context) ;;  # Nix context overrides (handled below)
            *) launch_args="$launch_args $arg" ;;
          esac
        done
        exec "$STRATA_HOME/.venv/bin/python" "$STRATA_HOME/strata.py" launch \
          ${if context != null then "-c ${context} " else ""} \
          $(echo $launch_args)
      '';
  };

  # --- `strata-chat`: terminal chat against a running Strata server ---
  strata-chat = writeShellApplication {
    name = "strata-chat";
    text = env
      + ''
        if [ ! -x "$STRATA_HOME/.venv/bin/python" ]; then
          echo "Strata: not set up yet - run 'strata' first." >&2
          exit 1
        fi
        cd "$STRATA_HOME"
        exec "$STRATA_HOME/.venv/bin/python" tools/chat.py "$@"
      '';
  };

  # --- `strata-server`: the always-on, engine-optional server behind the
  # Unsloth Studio integration.
  # Reinstalls the component from the store before starting (covers
  # `home-manager switch` service restarts). Same flags as before:
  # --lazy (when vision off), --idle-unload, --min-free-vram-mib,
  # --before-load, --host/--port, STRATA_CONFIG.
  strata-server = writeShellApplication {
    name = "strata-server";
    text = env
      + ''
        PY="$STRATA_HOME/.venv/bin/python"
        if [ ! -x "$PY" ]; then
          echo "Strata: not set up yet - run 'strata' once first." >&2
          exit 1
        fi
        # Re-assert --expert-cache on the configs before serving.
        ${configPatch}/bin/strata-patch-config
        # Re-install the engine component from the store (covers home-manager
        # switch service restarts: the store may have a newer engine).
        rm -rf "$STRATA_HOME/components"
        cp -r "${component}" "$STRATA_HOME/components/engine"
        CFG=""
        for f in "$STRATA_HOME"/strata-*.json; do
          [ -f "$f" ] || continue
          case "$f" in *.shared-settings.json) continue ;; esac
          grep -q '"args"' "$f" 2>/dev/null || continue
          if [ -z "$CFG" ] || [ "$f" -nt "$CFG" ]; then CFG="$f"; fi
        done
        if [ -n "''${STRATA_CONFIG:-}" ] && [ -f "''${STRATA_CONFIG}" ]; then
          CFG="$STRATA_CONFIG"
        fi
        if [ -z "$CFG" ]; then
          echo "Strata: no model configured - run 'strata' once first." >&2
          exit 1
        fi
        extra=(--host "''${STRATA_HOST:-127.0.0.1}" --port "''${STRATA_PORT:-8080}")
        ${lib.optionalString (!vision) "extra+=(--lazy)"}
        extra+=(--idle-unload "''${STRATA_IDLE_UNLOAD:-300}")
        if [ -n "''${STRATA_MIN_FREE_VRAM:-}" ]; then
          extra+=(--min-free-vram-mib "$STRATA_MIN_FREE_VRAM")
        fi
        if [ -n "''${STRATA_BEFORE_LOAD:-}" ]; then
          extra+=(--before-load "$STRATA_BEFORE_LOAD")
        fi
        exec "$PY" ${share}/serve/server.py --engine strata --config "$CFG" "''${extra[@]}"
      '';
  };
in
symlinkJoin {
  name = "strata-${version}";
  paths = [ runtime strata strata-chat strata-server ];
  # `runtimeShare` points at the runtime derivation only (no CUDA engine).
  # The flake's `strata-fail-closed` check runs ./config_patch.py against the
  # REAL strata_control/user_args.py through here.
  passthru = { runtimeShare = share; };
  meta = with lib; {
    version = "0.2.17";
    description = "Strata: local Qwen3.8-Flash-Next (125B MoE) inference with an OpenAI/Anthropic-compatible API";
    homepage = "https://github.com/Niko1221/Strata";
    license = licenses.mit;
    platforms = platforms.linux;
    mainProgram = "strata";
  };
}
