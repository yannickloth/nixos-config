# Strata 0.2.21 — NixOS packaging.
#
# Upstream 0.2.16 restructured the repo (Terminal → terminal/, Engine → engine/),
# and 0.2.16+ ships the engine as a versioned "component" with a per-file
# SHA-256 manifest (engine-component.json). Both `strata launch` (Terminal) and
# the desktop app install models through setup.py in CONTROL mode, writing
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
# engine (0.1.67), the Terminal (0.2.21, `strata.py` + `strata_cli`), and the
# desktop app (0.2.21). The engine is versioned apart from the app. The desktop
# AppImage is packaged separately (desktop.nix) and version-locked to the
# Terminal in the flake declaration (home.nix).
#
# Pictures (the strata-vision encoder) are a build-time choice only:
# `visionEncoder` says whether the package BUILDS and ships the encoder. Whether
# a model serves images is the run config's `vision` block, answered by
# `strata launch` and left alone by Nix. `preloadEngine` is the service's start
# behaviour: with it false, `strata-server` passes --lazy and the engine loads on
# the first request. Shipping the encoder costs only disk (~1.2 GB of VRAM and a
# few % of text speed are paid when a model uses it, plus ~0.9 GB of mmproj
# weights that setup downloads). See home.nix.
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
# - 0.2.18 adds the Tencent Hy4-Flash model and its own "shape" engine. That
#   engine is a SEPARATE component (components/shapes/<shape>/engine/...,
#   strata-hy4 0.1.67) which this package does not build; the Terminal and the
#   app fetch it from the signed feed when a Hy4-Flash pack is chosen. The
#   Qwen 125B keeps the Strata engine built here (0.1.67). Nothing else
#   changes for this package: same run-config keys, same --expert-cache rule,
#   same component manifest schema.
# - Component model: the engine is an installed component (~/.local/share/strata/
#   components/engine/<version>-<platform>-<backend>/) with a per-file manifest.
#   `strata launch` writes `exe: "component:strata-engine"`. The component is
#   installed from the store by `strata` and by `strata-server` (the latter
#   covers `home-manager switch` service restarts). It holds a small `strata`
#   wrapper (configPatch, then the store engine), the picture reader and
#   BUILD.json; the manifest (engine-component.json) is generated in the build
#   in the schema Control validates.

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
  visionEncoder ? false,
  isCachyOS ? false,
  preloadEngine ? false,
  strataSrc ? fetchFromGitHub {
    owner = "Niko1221";
    repo = "Strata";
    rev = "v0.2.21";  # App and Terminal 0.2.21; engine 0.1.67
    hash = "sha256-AhmGZPvxkBqFGsA2CDxiaiW1CwncjOuZESJX1G2Xv0A=";
  },
}:

let
  version = "0.2.21";
  engineVersion = "0.1.67";
  # The component folder name upstream's package_engine.py builds:
  #   f"{version}-{platform}-{backend}"  (0.1.67-linux-x86_64-cuda)
  componentDirName = "${engineVersion}-linux-x86_64-cuda";

  # The engine build's own id (read_manifest requires a non-empty one).
  buildId = "nix-${version}-engine-${engineVersion}-cuda12";

  # Config patch: run on every engine start to ensure --expert-cache is present
  # and a stale "vision" block cannot survive in a build without the encoder.
  # Also does one-time, idempotent migration of existing run configs from
  # path-based `exe` to `component:strata-engine` (the component model of
  # 0.2.16+). This is the enforcement point of the module policy.
  configPatch = writeShellApplication {
    name = "strata-patch-config";
    runtimeInputs = [ python3 ];
    text = ''
      python3 - ${share} ${lib.boolToString visionEncoder} ${componentDirName} <<'PY'
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

  # Environment preamble shared by every wrapper. ''${ is Nix's escape for a
  # literal ${ (an unescaped one would be interpolation).
  env = ''
    export STRATA_HOME="''${STRATA_HOME:-$HOME/.local/share/strata}"
    export PYTHONUTF8=1
    if [ -f /usr/lib/locale/locale-archive ] && ! grep -qs '^ID=nixos' /etc/os-release; then
      export LOCALE_ARCHIVE=/usr/lib/locale/locale-archive
    fi
    export LD_LIBRARY_PATH="${engine}/lib-driver:${pkgs.stdenv.cc.cc.lib}/lib:${pkgs.zlib}/lib''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
    if [ -e /run/opengl-driver/lib/libcuda.so.1 ]; then
      export LD_LIBRARY_PATH="/run/opengl-driver/lib:$LD_LIBRARY_PATH"
    fi
    export STRATA_IQ256_GATHER="''${STRATA_IQ256_GATHER:-1}"
  '';

  # --- Component ---
  # The engine installed as an upstream engine component. Control reads it at
  # ~/.local/share/strata/components/engine/<version>-<platform>-<backend>/
  # (strata_control/engine_component.py), so the folder name and the manifest
  # below must match what tools/packaging/package_engine.py produces:
  #
  #   {"schema_version": 2, "id": "strata-engine", "name": "strata-engine",
  #    "version": "0.1.67", "platform": "linux-x86_64", "backend": "cuda",
  #    "archs": ["sm_86", "compute_86"], "min_driver": {"nvidia": "575.51"},
  #    "build_id": "...", "entrypoint": "strata",
  #    "files": [{"path": ..., "sha256": ..., "bytes": ...}, ...],
  #    "signature": null}
  #
  # The component folder holds only small files. The engine ELF stays in the
  # store: `strata` is a wrapper that re-asserts --expert-cache (the web UI's
  # settings form drops flags it does not know) and then execs the store
  # binary. The picture reader must sit beside the entrypoint (serve/server.py,
  # with_current_reader), so strata-vision is copied in when it is built.
  #
  # read_manifest is strict: a missing schema_version/id/backend/entrypoint,
  # `files` as an object, `min_driver` as a string or `signature` as "" all
  # raise ComponentProblem and the engine is then invisible to Control.
  component = pkgs.runCommand "strata-component-${engineVersion}" {
    nativeBuildInputs = [ pkgs.python3 ];
    buildInputs = [ engine ];
  } ''
    dest=$out/${componentDirName}
    mkdir -p $dest

    # The entrypoint: re-assert the policy, then hand over to the engine.
    # NOT two `exec`s - the first one replaces this shell and the engine would
    # never start.
    cat > $dest/strata <<'WRAPPER'
    #!/bin/sh
    ${configPatch}/bin/strata-patch-config || exit $?
    exec "${engineBin}" "$@"
    WRAPPER
    chmod 755 $dest/strata

    # The picture reader, beside the entrypoint. -L: the engine derivation is a
    # symlinkJoin, so bin/strata-vision is a symlink and verify() refuses any
    # symlink in the component folder.
    ${lib.optionalString visionEncoder ''
      cp -L "${engineVisionBin}" $dest/strata-vision
    ''}

    # BUILD.json - the engine's own build record. setup.py/doctor.py read
    # "version"; package_lib_dirs reads "lib_dirs" (none: the RUNPATH carries
    # the CUDA libraries); package_engine.py reads "archs"/"vision_archs" as
    # arch numbers ("86").
    python3 - "$dest" "${engineVersion}" "${cudaArch}" \
      "${if visionEncoder then "true" else "false"}" <<'BUILDJSON'
    import json, sys
    dest, version, arch, vision = sys.argv[1:5]
    meta = {"version": version, "source": "nix", "archs": arch, "portable": True, "lib_dirs": []}
    if vision == "true":
        meta["vision_archs"] = arch
    with open(dest + "/BUILD.json", "w", encoding="utf-8") as f:
        json.dump(meta, f, indent=1)
    BUILDJSON

    # The manifest: schema 2, exactly the shape read_manifest() validates.
    # It hashes the files it lists (BUILD.json included) and is not listed
    # itself. `signature: null` is the unsigned local build; STRATA_REQUIRE_
    # SIGNED_COMPONENTS would refuse it, nothing else does.
    python3 - "$dest" "${engineVersion}" "${cudaArch}" "${buildId}" <<'MANIFEST'
    import hashlib, json, os, sys
    dest, version, arch, build_id = sys.argv[1:5]
    files = []
    for name in sorted(os.listdir(dest)):
        path = os.path.join(dest, name)
        if name == "engine-component.json" or not os.path.isfile(path):
            continue
        with open(path, "rb") as f:
            data = f.read()
        files.append({"path": name, "sha256": hashlib.sha256(data).hexdigest(), "bytes": len(data)})
    manifest = {
        "schema_version": 2,
        "id": "strata-engine",
        "name": "strata-engine",
        "version": version,
        "platform": "linux-x86_64",
        "backend": "cuda",
        "archs": ["sm_" + arch, "compute_" + arch],
        "min_driver": {"nvidia": "575.51"},
        "build_id": build_id,
        "entrypoint": "strata",
        "files": files,
        "signature": None,
    }
    with open(os.path.join(dest, "engine-component.json"), "w", encoding="utf-8") as f:
        json.dump(manifest, f, indent=1)
        f.write("\n")
    MANIFEST
  '';

  # Install/refresh the component from the store. Called by `strata` and by
  # `strata-server` (the latter covers `home-manager switch` service restarts).
  #
  # Path: upstream derives it from XDG_DATA_HOME, not from STRATA_HOME, so the
  # same rule is used here. A stamp makes this a no-op when the store component
  # is already installed: the folder is small, but this runs on every CLI call.
  componentInstall = writeShellApplication {
    name = "strata-install-component";
    runtimeInputs = [ coreutils ];
    text = ''
      comps="''${STRATA_COMPONENTS_DIR:-''${XDG_DATA_HOME:-$HOME/.local/share}/strata/components}"
      dest="$comps/engine/${componentDirName}"
      stamp="$comps/engine/.nix-component"

      want="${component}"
      if [ "$(cat "$stamp" 2>/dev/null || true)" = "$want" ] && [ -f "$dest/engine-component.json" ]; then
        exit 0
      fi

      mkdir -p "$comps/engine"
      # The store's directories are read-only, so `rm -rf` cannot unlink what a
      # previous copy left behind. Make the tree writable first.
      chmod -R u+w "$comps/engine" 2>/dev/null || true
      # Nix owns the engine: drop every other package (an engine `strata
      # update` downloaded, an older version). .updates/ is left alone.
      for d in "$comps/engine"/*; do
        [ -d "$d" ] || continue
        [ "$d" = "$dest" ] && continue
        rm -rf "$d"
      done
      rm -rf "$dest"
      cp -r "$want/${componentDirName}" "$dest"
      chmod -R u+w "$dest"
      printf '%s\n' "$want" > "$stamp"
    '';
  };

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

        # Refresh the program files from the store. This is upstream's own
        # TERMINAL_ENTRIES list (setup.py) - every folder a Terminal install
        # has at its root. Only those are replaced; model files, packs, logs
        # and run configs are left alone.
        for d in tools data serve strata_cli strata_control ref crates integrations bin; do
          chmod -R u+rwX "$STRATA_HOME/$d" 2>/dev/null || true
          rm -rf "''${STRATA_HOME:?}/$d"
          cp -r "${share}/$d" "$STRATA_HOME/"
          chmod -R u+rwX "$STRATA_HOME/$d"
        done
        for f in setup.py strata.py requirements.txt requirements-monitor.txt requirements-nvfp4-local.txt; do
          install -m644 ${share}/$f "$STRATA_HOME/" 2>/dev/null || true
        done

        # Install/refresh the engine component from the store.
        ${componentInstall}/bin/strata-install-component

        # Legacy engine directory cleanup: if the old `engine/` dir exists and
        # holds no model data, remove it. 0.2.16 looks the engine up in the
        # component folder; a leftover engine/ tree makes setup.py read the
        # runtime root as a source checkout. (Capture the find result instead
        # of piping into grep -q: under `set -o pipefail` grep's early exit
        # makes find report SIGPIPE and the test would say "no model data".)
        if [ -d "$STRATA_HOME/engine" ] && [ -z "$(find "$STRATA_HOME/engine" \( -name '*.gguf' -o -name '*.bin' \) -print -quit 2>/dev/null)" ]; then
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
        # --setup = removed (launch is the default), --vision yes/no = on/off.
        # Everything else - --context, --model, --kv, --tune - is passed to
        # `launch` as typed; Nix injects no engine flag.
        # A sub-command goes to the CLI unchanged. This list is upstream's own
        # parser (strata_cli/cli.py, the _SubParsersAction): anything missing
        # here would be handed to `launch` and rejected as an unknown flag, so
        # `strata launch` itself and `strata split-engine` are in it too.
        # When running `strata launch` the wrapper inserts --api-key-env
        # STRATA_API_KEY (unless the user already set --api-key or --api-key-env
        # explicitly), so the TUI reads the key from the environment instead of
        # generating a random one on first setup.
        add_api_key_env() {
          has_key=0
          for a in "$@"; do
            case "$a" in --api-key*|--no-api-key) has_key=1 ;; esac
          done
          if [ "$has_key" -eq 0 ] && [ -n "''${STRATA_API_KEY:-}" ]; then
            set -- "$@" "--api-key-env" "STRATA_API_KEY"
          fi
        }

        case "''${1:-}" in
          -h | --help | -V | --version | \
          launch | serve | bench | code | complete | components | config | connect | \
          connection | doctor | drafting | engine | install | logs | models | monitor | ops | \
          presets | profile | repair-access | runtime | split-engine | status | timeskip | \
          tune | update)
            # For 'strata launch' only, inject the env-var reader so a random
            # key is never generated (the key comes from STRATA_API_KEY set by
            # the systemd unit / home.sessionVariables).  If the user already
            # passed --api-key/--api-key-env/--no-api-key the wrapper stays out.
            if [ "''${1}" = "launch" ]; then
              shift; set -- launch "$@"
              add_api_key_env "$@"
            fi
            exec "$STRATA_HOME/.venv/bin/python" "$STRATA_HOME/strata.py" "$@"
            ;;
        esac

        # Legacy mapping: bare `strata` = `launch`. Transform --vision yes/no -> on/off,
        # pass every other flag through. A bash array keeps arguments with spaces
        # intact. Also injects --api-key-env STRATA_API_KEY unless the user
        # already passed --api-key/--api-key-env/--no-api-key (same check as
        # add_api_key_env above) so we do not override an explicit --no-api-key.
        launch_args=()
        has_key=0
        for arg in "$@"; do
          case "$arg" in
            --setup | "-s") ;;                                # no-op - launch is the default
            --vision=yes) launch_args+=(--vision on) ;;
            --vision=no) launch_args+=(--vision off) ;;
            *) launch_args+=("$arg") ;;
          esac
          case "$arg" in --api-key*|--no-api-key) has_key=1 ;; esac
        done
        if [ "$has_key" -eq 0 ] && [ -n "''${STRATA_API_KEY:-}" ]; then
          launch_args+=("--api-key-env" "STRATA_API_KEY")
        fi
        exec "$STRATA_HOME/.venv/bin/python" "$STRATA_HOME/strata.py" launch "''${launch_args[@]}"
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
  # --lazy (when preloadEngine is false), --idle-unload, --min-free-vram-mib,
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
        ${componentInstall}/bin/strata-install-component
        # What to serve, in order of precedence:
        #
        # 1. STRATA_CONFIG (set by the `strata.defaultConfig` option): an
        #    absolute path, or a name under $STRATA_HOME. It wins over
        #    everything, because naming one config is an explicit decision.
        # 2. The newest run config `strata launch` wrote:
        #    $XDG_STATE_HOME/strata/launch/<name>.json (upstream's
        #    strata_cli/launch/runner.py:746). The launch screens answer every
        #    engine choice - model, context, kv, vision, drafting, cards - and
        #    launch writes the answers there as a run config. So the unit starts
        #    what the last `strata launch` specified. Sidecars in that folder
        #    (*.choices.json, *.tune.json) are not run configs: they carry no
        #    "args", and the greedy test below skips them.
        # 3. The newest setup-era config in $STRATA_HOME (strata-*.json), for a
        #    host that has never run `strata launch`: the desktop app and the
        #    old `strata --setup` write these.
        #
        # A launch preset saved with no start (no run config yet) cannot be
        # served here: it holds choices, not engine arguments. Start that preset
        # once (`strata launch --preset NAME`) to write its run config.
        CFG=""
        LAUNCH_DIR="''${XDG_STATE_HOME:-$HOME/.local/state}/strata/launch"
        for f in "$LAUNCH_DIR"/*.json; do
          [ -f "$f" ] || continue
          case "$f" in *.choices.json | *.shared-settings.json | *.tune.json) continue ;; esac
          grep -q '"args"' "$f" 2>/dev/null || continue
          if [ -z "$CFG" ] || [ "$f" -nt "$CFG" ]; then CFG="$f"; fi
        done
        if [ -z "$CFG" ]; then
          for f in "$STRATA_HOME"/strata-*.json; do
            [ -f "$f" ] || continue
            case "$f" in *.shared-settings.json) continue ;; esac
            grep -q '"args"' "$f" 2>/dev/null || continue
            if [ -z "$CFG" ] || [ "$f" -nt "$CFG" ]; then CFG="$f"; fi
          done
        fi
        if [ -n "''${STRATA_CONFIG:-}" ]; then
          case "''${STRATA_CONFIG}" in
            /*) asked="''${STRATA_CONFIG}" ;;
            *) asked="$STRATA_HOME/''${STRATA_CONFIG}" ;;
          esac
          if [ -f "$asked" ]; then
            CFG="$asked"
          else
            echo "Strata: STRATA_CONFIG=$STRATA_CONFIG is not a file - ignored, the newest run config is served instead." >&2
          fi
        fi
        if [ -z "$CFG" ]; then
          echo "Strata: no model configured - run 'strata launch' once first." >&2
          exit 1
        fi
        echo "Strata: serving $(basename "$CFG")" >&2
        # A preset that was saved but never started has no run config, so the
        # unit cannot follow it. Say so once per start instead of serving the
        # previous model without a word. `last_used` is set by the first start of
        # the preset, so a preset saved after a successful launch stays quiet.
        PRESET_DIR="''${XDG_CONFIG_HOME:-$HOME/.config}/strata/launch-presets"
        for p in "$PRESET_DIR"/*.json; do
          [ -f "$p" ] || continue
          [ "$p" -nt "$CFG" ] || continue
          grep -Eq '"last_used"[[:space:]]*:[[:space:]]*null' "$p" 2>/dev/null || continue
          echo "Strata: the launch preset '$(basename "$p" .json)' was saved but never started, so it has no run config yet. Start it once (strata launch --preset NAME) to make the unit follow it." >&2
          break
        done
        extra=(--host "''${STRATA_HOST:-127.0.0.1}" --port "''${STRATA_PORT:-8080}")
        ${lib.optionalString (!preloadEngine) "extra+=(--lazy)"}
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
    version = version;
    description = "Strata: local Qwen3.8-Flash-Next (125B MoE) inference with an OpenAI/Anthropic-compatible API";
    homepage = "https://github.com/Niko1221/Strata";
    license = licenses.mit;
    platforms = platforms.linux;
    mainProgram = "strata";
  };
}
