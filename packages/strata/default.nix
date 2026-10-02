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
# Runtime notes (laptop-p16, established 2026-09-27 - see also engine.nix):
# - The wrapper and `strata-server` enforce a declarative engine policy on
#   every config (the module options, see home.nix): --max-context (default
#   524288, with yarn factor 2 past the trained 262144), --kv / --kv-resident
#   (8-bit, streamed from pinned RAM) and --vram-reserve-mib 1800 (the auto
#   expert cache otherwise fills VRAM and the first request dies with "verify:
#   instantiate: out of memory"). --expert-cache must stay: the engine refuses
#   to serve native packs at large contexts without it.
# - Native (IQ) packs REQUIRE --spec >= 2: the engine refuses to start
#   without it, and deeper is faster (spec 4 > spec 2: 6.3 vs 5.6 tok/s).
# - The engine only resolves libcuda through the wrapper's LD_LIBRARY_PATH
#   (the lib-driver dir, see ./engine.nix): launching serve/server.py by hand
#   without it fails with a misleading "cannot pin 322 MiB: CUDA driver
#   version is insufficient".
# - Measured speed (0.1.31+, fixed 22-token prompt, bench/a3000-tune.sh):
#   ~28-33 tok/s decode; the 0.1.18-era ~6 tok/s figure predates the engine
#   fixes upstream landed in 0.1.19-0.1.31. Interactive-snappy local chat
#   stays on unsloth-studio's 9B GGUFs; this is the quality endpoint for
#   opencode.
{
  lib
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
  # Engine config policy, enforced on every engine config the package writes
  # (see configPatch below). Default: one 512K-context Strata - the model's
  # trained 262144 extended by yarn factor 2 - with the KV cache 8-bit and
  # streamed from pinned RAM. See packages/strata/home.nix for the options.
  , context ? 524288
  , kv ? "int8"
  , kvResident ? 32768
  , ropeScaling ? "yarn"
  # Measured hardware tuning from tools/calibrate.py (see the bench/results
  # entry for this host in the fork). null leaves the engine's own default: the
  # PCIe probe for --pcie-frac, 0.5 for --spec-min-p, and every physical core
  # minus the host's for --pool-workers.
  , pcieFrac ? null
  , specMinP ? null
  , poolWorkers ? null
  , poolAffinity ? null
  # Source: the `forksStrata` flake input (github.com/yannickloth/forks-Strata,
  # branch perf/am47) - upstream 0.1.35 (d9ab843) plus the sm_86 work: the
  # native-embedding error report and the A3000 bench harness. (The Q4_K/Q5_K/
  # Q5_1 MMQ instances this branch used to carry are upstream as of 0.1.32,
  # behind STRATA_MMQ_KQUANTS.) Passed in from flake.nix and home.nix;
  # `nix flake update forksStrata` moves it to the branch head. The private repo
  # is fetched over ssh with the invoking user's key - a fetchFromGitHub/fetchgit
  # derivation cannot authenticate to it (the nix daemon runs as root without
  # that key), which is why it is a flake input, not a fetcher derivation.
  , strataSrc
  , llamaCpp ? fetchFromGitHub {
    owner = "ggml-org";
    repo = "llama.cpp";
    rev = "3cf03257f219afbe7334045ff7c6a06ac68c627d";
    hash = "sha256-SRGoXa+4ACBCB3eaG9XFYhMN1i0FyPEy9Rrer+dFGYI=";
  }
,
}:

let
  version = "0.1.35";

  # VRAM kept free of expert-cache slots so request-time buffers (verify
  # graphs, prompt borrows, vision activations) never OOM; the auto sizer
  # otherwise fills VRAM completely.
  vramReserveMiB = if vision then 2800 else 1800;

  # "none" sentinel: an argument the configPatch below must leave unset (the
  # engine keeps its own default), for the calibrated knobs that are optional.
  optArg = v: if v == null then "none" else toString v;
  # Numbers via toJSON so a float renders as "0.35", not Nix's "0.350000".
  jsonArg = v: if v == null then "none" else builtins.toJSON v;

  # Declarative engine policy: rewrite the args of every engine config under
  # STRATA_HOME so the served model always matches the module options, whatever
  # `strata --setup` answered. Runs from both the `strata` and `strata-server`
  # wrappers (idempotent). --max-context/--kv/--kv-resident/--rope-scaling are
  # exactly what setup.py itself would write for `--context <context>`, but from
  # Nix instead of a runtime answer; --vram-reserve-mib stays enforced as before.
  configPatch = writeShellApplication {
    name = "strata-patch-config";
    runtimeInputs = [ python3 ];
    text = ''
      python3 - ${toString context} ${lib.escapeShellArg kv} ${toString kvResident} ${lib.escapeShellArg ropeScaling} ${toString vramReserveMiB} ${jsonArg pcieFrac} ${jsonArg specMinP} ${jsonArg poolWorkers} ${lib.escapeShellArg (optArg poolAffinity)} <<'PY'
      import glob, json, os, sys
      ctx, kv, kv_res, rope, vram, pcie, spec, workers, affinity = (
          int(sys.argv[1]), sys.argv[2], int(sys.argv[3]), sys.argv[4], int(sys.argv[5]),
          sys.argv[6], sys.argv[7], sys.argv[8], sys.argv[9])
      home = os.environ.get("STRATA_HOME") or os.path.expanduser("~/.local/share/strata")

      def set_opt(args, flag, value):
          # drop every occurrence of flag (and its value, if it takes one), then
          # append it at the end when value is not None
          out, i = [], 0
          while i < len(args):
              if args[i] == flag:
                  i += 1
                  if i < len(args) and not args[i].startswith("--"):
                      i += 1
                  continue
              out.append(args[i]); i += 1
          if value is not None:
              out += [flag, str(value)]
          return out

      for p in sorted(glob.glob(os.path.join(home, "strata-*.json"))):
          if p.endswith(".shared-settings.json"):     # the web app's Chat settings, not a model
              continue
          try:
              with open(p, encoding="utf-8") as f:
                  c = json.load(f)
              if not isinstance(c, dict) or not isinstance(c.get("args"), list):
                  continue
              a = c["args"]
              if ctx > 0:
                  a = set_opt(a, "--max-context", ctx)
              if kv:
                  a = set_opt(a, "--kv", kv)
              # k8v4 never streams its KV (the engine refuses the combination)
              if kv == "k8v4" or kv_res <= 0:
                  a = set_opt(a, "--kv-resident", None)
              else:
                  a = set_opt(a, "--kv-resident", kv_res)
              # past the trained 262144 the angles must be rescaled; inside it,
              # keep the model completely stock (no rope flags at all)
              if ctx > 262144:
                  a = set_opt(a, "--rope-scaling", rope)
                  a = set_opt(a, "--rope-scale", f"{ctx / 262144:g}")
              else:
                  a = set_opt(a, "--rope-scaling", None)
                  a = set_opt(a, "--rope-scale", None)
              a = set_opt(a, "--vram-reserve-mib", vram)
              # Calibrated hardware knobs (tools/calibrate.py): set only when the
              # module provided them, otherwise the engine's default/probe stands.
              if pcie != "none":
                  a = set_opt(a, "--pcie-frac", pcie)
              if spec != "none":
                  a = set_opt(a, "--spec-min-p", spec)
              if workers != "none":
                  a = set_opt(a, "--pool-workers", workers)
              if affinity != "none":
                  a = set_opt(a, "--pool-affinity", affinity)
              c["args"] = a
              with open(p, "w", encoding="utf-8") as f:
                  json.dump(c, f, indent=1)
          except Exception as e:
              print(f"strata: could not patch {p}: {e}", file=sys.stderr)
      PY
    '';
  };

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

        # Declarative engine policy (max-context, KV format, rope scaling) and
        # the VRAM reserve are enforced on every config here and again in
        # strata-server (see configPatch above). NOTE: --expert-cache must
        # STAY: the engine refuses to serve native packs at large contexts
        # without it ("needs --spec T, ... and --expert-cache"). Upstream warns
        # its GPU hit path can diverge from a cache-off run; with the cache
        # mandatory there is no off switch to fall back on.
        ${configPatch}/bin/strata-patch-config

        # First-run setup must write this context too, not whatever the
        # interactive default offers (setup.py then derives the matching yarn
        # factor itself). An explicit --context on the command line still wins;
        # configPatch above re-normalizes KV and rope args regardless.
        want_context=0
        for arg in "$@"; do
          case "$arg" in --context | --context=*) want_context=1 ;; esac
        done
        if [ "$want_context" = 0 ]; then
          set -- "$@" --context "${toString context}"
        fi

        # The model wants the A3000's full 12 GB of VRAM and tens of GB of
        # RAM, so free them: stop the GPU-resident user services (unsloth-
        # studio, laya-mcp) when the model is actually about to start
        # (--setup/--check/--no-start don't). Restart afterwards with
        # systemctl --user start <unit>.
        start_model=1
        for arg in "$@"; do
          case "$arg" in
            --setup | --check | --no-start) start_model=0 ;;
          esac
        done
        if [ "$start_model" = 1 ]; then
          for unit in strata unsloth-studio laya-mcp; do
            if systemctl --user is-active --quiet "$unit" 2>/dev/null; then
              echo "Strata: stopping $unit (frees VRAM/RAM for the model)..." >&2
              systemctl --user stop "$unit"
            fi
          done
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

  # The always-on, engine-optional server for the Unsloth Studio integration
  # (systemd user service, see ./home.nix). `--lazy` (upstream's replacement
  # for the fork's removed `--no-preload`) means it serves with NO engine
  # loaded: the first request starts it, and it unloads itself after
  # STRATA_IDLE_UNLOAD seconds (default 300) without one - so a machine can
  # host this model and Studio's own models without either holding the GPU
  # forever. No setup.py: no service stopping, no browser, no downloading.
  # The store's serve/ is used directly (ROOT resolves to share/strata, whose
  # tools/ has the tokenizer module); paths inside the config are absolute.
  strata-server = writeShellApplication {
    name = "strata-server";
    text =
      env
      + ''
        PY="$STRATA_HOME/.venv/bin/python"
        if [ ! -x "$PY" ]; then
          echo "Strata: not set up yet - run 'strata' once first (first-run setup)." >&2
          exit 1
        fi
        # Re-assert the declarative engine policy (max-context, KV, rope) on the
        # configs before serving; a config edited by hand or written by setup.py
        # is brought back in line here too.
        ${configPatch}/bin/strata-patch-config
        # Point the engine at THIS build. The `strata` wrapper does this during
        # setup, but the server is what a `home-manager switch` restart runs, so
        # without it an upgrade would keep serving the older store engine (the
        # config's `exe` is the engine/strata symlink).
        mkdir -p "$STRATA_HOME/engine"
        ln -sfn "${engine}/bin/strata" "$STRATA_HOME/engine/strata"
        printf '%s\n' '{"source": "local", "version": "${version}", "archs": [${cudaArch}], "vision": "${if vision then "gpu" else "none"}", "cuda_dirs": []}' \
          > "$STRATA_HOME/engine/BUILD.json"
        CFG=""
        for f in "$STRATA_HOME"/strata-*.json; do
          [ -f "$f" ] || continue                       # no config at all: the glob stays literal
          case "$f" in *.shared-settings.json) continue ;; esac   # the web app's Chat settings, not a model
          grep -q '"args"' "$f" 2>/dev/null || continue           # an engine config carries args
          if [ -z "$CFG" ] || [ "$f" -nt "$CFG" ]; then CFG="$f"; fi
        done
        # STRATA_CONFIG pins the served model when several are configured;
        # without it the most recently written config wins.
        if [ -n "''${STRATA_CONFIG:-}" ] && [ -f "''${STRATA_CONFIG}" ]; then
          CFG="$STRATA_CONFIG"
        fi
        if [ -z "$CFG" ]; then
          echo "Strata: no model configured - run 'strata' once first." >&2
          exit 1
        fi
        exec "$PY" ${share}/serve/server.py --engine strata --config "$CFG" \
          --host 127.0.0.1 --port "''${STRATA_PORT:-8080}" \
          ${lib.optionalString (!vision) "--lazy "}--idle-unload "''${STRATA_IDLE_UNLOAD:-300}"
      '';
  };
in
symlinkJoin {
  name = "strata-${version}";
  paths = [
    runtime
    strata
    strata-chat
    strata-server
  ];
  meta = with lib; {
    description = "Strata: local Qwen3.8-Flash-Next (125B MoE) inference with an OpenAI/Anthropic-compatible API";
    homepage = "https://github.com/Niko1221/Strata";
    license = licenses.mit; # upstream's LICENSE (see ./engine.nix)
    platforms = platforms.linux;
    mainProgram = "strata";
  };
}
