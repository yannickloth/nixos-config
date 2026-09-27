# CLM (Contrastive Language Models) — a System 1 decision engine, packaged for
# home-manager, in the same style as ../laya.
#
# This is deliberately *not* a uv2nix build of the Python environment: the
# torch/CUDA and vLLM wheels are multi-GB and are fetched at runtime, so the
# package ships the CLI wrappers plus the locked uv project and creates the
# virtualenv on first use at ~/.local/share/clm/venv (override with CLM_VENV).
#
# Architecture (see https://github.com/Contrastive-LM/CLM):
#   clm-encode  vLLM Qwen3-8B pooling encoder  (GPU, :8090, /v1/embeddings)
#   clm-serve   CLM head server + playground   (CPU, :8700, /v1/systemone)
# The 75 MB reference head is downloaded into ~/.cache/clm/ on first use.
#
# Scope wrapper: ./home.nix (home-manager, `clm.enable`) — it runs both pieces
# as systemd user services.
{ lib
, stdenv
, symlinkJoin
, writeShellApplication
, uv
,
}:

let
  version = "0.1.0";

  # The uv project (pyproject.toml + uv.lock), kept read-only in the store; the
  # venv is created outside it via UV_PROJECT_ENVIRONMENT, because
  # `uv sync` cannot write into the store.
  data = stdenv.mkDerivation {
    pname = "clm-data";
    inherit version;
    src = ./.;
    dontBuild = true;
    installPhase = ''
      runHook preInstall
      mkdir -p $out/share/clm/project
      cp pyproject.toml uv.lock $out/share/clm/project/
      runHook postInstall
    '';
  };

  share = "${data}/share/clm";

  # Shared launcher preamble. `''${...}` is a literal `${...}` for the shell.
  env = ''
    export UV_PROJECT_ENVIRONMENT="''${CLM_VENV:-$HOME/.local/share/clm/venv}"
    export USE_TF=0
    export LD_LIBRARY_PATH="/run/opengl-driver/lib''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
  '';

  # Message for the not-yet-created venv, shared by all launchers.
  missing = "CLM: environment not created yet — run 'clm-setup' (first run downloads torch/vLLM/CUDA, several GB).";

  mkScript = name: text: writeShellApplication {
    inherit name;
    runtimeInputs = [ uv ];
    text = env + text;
  };

  # Create/refresh the uv environment on demand.
  clm-setup = mkScript "clm-setup" ''
    exec uv sync --frozen --project ${share}/project --python 3.12 "$@"
  '';

  # The venv's Python (REPL when given no args), so `import clm` works.
  clm-python = mkScript "clm-python" ''
    if [ ! -x "$UV_PROJECT_ENVIRONMENT/bin/python" ]; then
      echo "CLM: creating environment (downloads torch/vLLM/CUDA, several GB)..." >&2
      uv sync --frozen --project ${share}/project --python 3.12 >&2
    fi
    exec "$UV_PROJECT_ENVIRONMENT/bin/python" "$@"
  '';

  # The Qwen3-8B pooling encoder clm-serve scores states and actions against
  # (the GPU half; serve_qwen3_8b.sh upstream). Qwen3-8B bf16 needs ~17 GB of
  # VRAM and downloads the backbone to the HF cache on first start. Exits 0
  # when the venv is absent so a service manager does not restart-loop and
  # download gigabytes on its own — run `clm-setup` first.
  clm-encode = mkScript "clm-encode" ''
    if [ ! -x "$UV_PROJECT_ENVIRONMENT/bin/vllm" ]; then
      echo "${missing}" >&2
      exit 0
    fi
    export CLM_EMB_MODEL="''${CLM_EMB_MODEL:-qwen3-8b}"
    exec "$UV_PROJECT_ENVIRONMENT/bin/vllm" serve "''${CLM_ENCODER_MODEL:-Qwen/Qwen3-8B}" \
      --served-model-name "$CLM_EMB_MODEL" \
      --runner pooling \
      --max-model-len "''${CLM_MAX_MODEL_LEN:-2048}" \
      --host "''${CLM_EMB_HOST:-127.0.0.1}" \
      --port "''${CLM_EMB_PORT:-8090}" \
      "$@"
  '';

  # The CLM API server (typed questions + playground). Exits 0 when the venv
  # is absent (see clm-encode); the 75 MB reference head downloads into
  # ~/.cache/clm/ on first start.
  clm-serve = mkScript "clm-serve" ''
    if [ ! -x "$UV_PROJECT_ENVIRONMENT/bin/clm-serve" ]; then
      echo "${missing}" >&2
      exit 0
    fi
    export CLM_PORT="''${CLM_PORT:-8700}"
    export CLM_EMB_URL="''${CLM_EMB_URL:-http://127.0.0.1:''${CLM_EMB_PORT:-8090}/v1/embeddings}"
    export CLM_EMB_MODEL="''${CLM_EMB_MODEL:-qwen3-8b}"
    exec "$UV_PROJECT_ENVIRONMENT/bin/clm-serve" "$@"
  '';

  # Fetch the released reference head into ~/.cache/clm/ ahead of time.
  clm-download = mkScript "clm-download" ''
    if [ ! -x "$UV_PROJECT_ENVIRONMENT/bin/clm-download" ]; then
      echo "${missing}" >&2
      exit 1
    fi
    exec "$UV_PROJECT_ENVIRONMENT/bin/clm-download" "$@"
  '';

  # Built-in typed-questions example against a running clm-serve, run end to
  # end. Inlined as a heredoc so no .py file is installed as a launcher.
  clm-demo = mkScript "clm-demo" ''
    if [ ! -x "$UV_PROJECT_ENVIRONMENT/bin/python" ]; then
      echo "${missing}" >&2
      exit 1
    fi
    exec "$UV_PROJECT_ENVIRONMENT/bin/python" - <<'PY'
    import json, sys
    from clm import CLMClient, Choice, Noul, Score

    client = CLMClient()  # CLM_BASE_URL (default http://127.0.0.1:8700), CLM_API_KEY
    state = {
        "from": "user@acme.com",
        "subject": "Duplicate charge on invoice #4411",
        "body": "We were billed twice for March. Please refund the duplicate today or we will cancel our plan.",
    }
    questions = {
        "department": Choice(instructions="Which team should handle this?",
                             criteria={"billing": "Charges, invoices, refunds",
                                       "technical": "Bugs and outages"}),
        "urgency": Score(instructions="How urgent is this request?",
                         criteria=["not urgent", "soon", "critical deadline or blocking issue"]),
        "churn_risk": Noul(instructions="Does the user threaten to cancel or leave?"),
    }

    try:
        r = client.system_one(state=state, questions=questions)
    except Exception as exc:
        print(f"CLM: cannot reach clm-serve ({exc}); is the 'clm-serve' user service up?", file=sys.stderr)
        sys.exit(1)

    print("Department :", r.answers["department"].choice, f"(confidence: {r.answers['department'].confidence:.2f})")
    print("Urgency    :", f"{r.answers['urgency'].score:.2f} / 2.0")
    print("Churn risk :", f"{r.answers['churn_risk'].noul:.1%}")
    print("\nFull result:")
    print(json.dumps({
        "answers": {k: v.model_dump() for k, v in r.answers.items()},
        "usage": {"input_tokens": r.usage.input_tokens},
        "latency_ms": r.latency_ms,
    }, indent=2))
    PY
  '';
in
symlinkJoin {
  name = "clm-${version}";
  paths = [
    data
    clm-setup
    clm-python
    clm-encode
    clm-serve
    clm-download
    clm-demo
  ];
  meta = with lib; {
    description = "CLM System 1 decision engine (encoder + API server launchers)";
    homepage = "https://github.com/Contrastive-LM/CLM";
    license = licenses.asl20;
    platforms = platforms.linux;
    mainProgram = "clm-serve";
  };
}
