# Laya (Convai Innovations) — a System 1 decision engine, packaged for reuse
# from both NixOS and home-manager.
#
# This is deliberately *not* a uv2nix build of the Python environment: the
# torch/CUDA wheels and the model checkpoints are multi-GB and are fetched at
# runtime, so the package ships the CLI wrappers plus the locked uv project and
# creates the virtualenv on first use at ~/.local/share/laya/venv (override with
# LAYA_VENV). Scope wrappers live alongside: ./home.nix (home-manager,
# `laya.enable`) and ./nixos.nix (NixOS, `services.laya.enable`).
{ lib
, stdenv
, symlinkJoin
, writeShellApplication
, uv
,
}:

let
  version = "0.3.3";

  # The uv project (pyproject.toml + uv.lock) and the MCP server script, kept
  # read-only in the store; the venv is created outside it via
  # UV_PROJECT_ENVIRONMENT, because `uv sync` cannot write into the store.
  data = stdenv.mkDerivation {
    pname = "laya-data";
    inherit version;
    src = ./.;
    dontBuild = true;
    installPhase = ''
      runHook preInstall
      mkdir -p $out/share/laya/project
      cp mcp_server.py $out/share/laya/mcp_server.py
      cp pyproject.toml uv.lock $out/share/laya/project/
      runHook postInstall
    '';
  };

  share = "${data}/share/laya";

  # Shared launcher preamble. `''${...}` is a literal `${...}` for the shell.
  env = ''
    export UV_PROJECT_ENVIRONMENT="''${LAYA_VENV:-$HOME/.local/share/laya/venv}"
    export USE_TF=0
    export LD_LIBRARY_PATH="/run/opengl-driver/lib''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
  '';

  mkScript = name: text: writeShellApplication {
    inherit name;
    runtimeInputs = [ uv ];
    text = env + text;
  };

  # Create/refresh the uv environment on demand.
  laya-setup = mkScript "laya-setup" ''
    exec uv sync --frozen --project ${share}/project --python 3.12 "$@"
  '';

  # The venv's Python (REPL when given no args), so `import laya` works.
  laya-python = mkScript "laya-python" ''
    if [ ! -x "$UV_PROJECT_ENVIRONMENT/bin/python" ]; then
      echo "Laya: creating environment (downloads PyTorch/CUDA, several GB)..." >&2
      uv sync --frozen --project ${share}/project --python 3.12 >&2
    fi
    exec "$UV_PROJECT_ENVIRONMENT/bin/python" "$@"
  '';

  # Streamable-HTTP MCP server consumed by MCP clients (opencode). Exits 0 when
  # the venv is absent so a service manager does not restart-loop and download
  # gigabytes on its own — run `laya-setup` first.
  laya-mcp = mkScript "laya-mcp" ''
    export LAYA_MCP_PORT="''${LAYA_MCP_PORT:-8765}"
    if [ ! -x "$UV_PROJECT_ENVIRONMENT/bin/python" ]; then
      echo "Laya: environment not created yet — run 'laya-setup' (first run downloads PyTorch/CUDA, several GB)." >&2
      exit 0
    fi
    exec "$UV_PROJECT_ENVIRONMENT/bin/python" ${share}/mcp_server.py
  '';

  # Built-in English example, run end to end. Inlined as a heredoc so no .py
  # file is installed as a launcher.
  laya-demo = mkScript "laya-demo" ''
    if [ ! -x "$UV_PROJECT_ENVIRONMENT/bin/python" ]; then
      echo "Laya: creating environment (downloads PyTorch/CUDA, several GB)..." >&2
      uv sync --frozen --project ${share}/project --python 3.12 >&2
    fi
    exec "$UV_PROJECT_ENVIRONMENT/bin/python" - <<'PY'
    import os, json
    os.environ.setdefault("USE_TF", "0")
    import torch, laya

    device = os.environ.get("LAYA_DEVICE") or ("cuda" if torch.cuda.is_available() else "cpu")
    print(f"Loading convaiinnovations/laya on {device} ...", flush=True)
    agent = laya.load("convaiinnovations/laya", device=device)

    state = {
        "from": "user@acme.com",
        "subject": "Duplicate charge on invoice #4411",
        "body": "We were billed twice for March. Please refund the duplicate today or we will cancel our plan.",
    }
    questions = {
        "department": {
            "type": "choice",
            "instructions": "Which department should handle this email?",
            "criteria": {
                "billing": "invoices, payments, refunds",
                "technical": "bugs, outages, system errors",
                "sales": "pricing, new contracts",
                "other": "everything else",
            },
        },
        "urgency": {
            "type": "score",
            "instructions": "How urgent is this request?",
            "criteria": ["not urgent", "soon", "critical deadline or blocking issue"],
        },
        "churn_risk": {
            "type": "noul",
            "instructions": "Does the user threaten to cancel or leave?",
        },
    }

    result = agent.predict(state, questions)
    answers = result["answers"]
    print(f"\nState: {state['subject']}")
    print("Department :", answers["department"]["choice"], f"(confidence: {answers['department']['confidence']:.2f})")
    print("Urgency    :", f"{answers['urgency']['score']:.2f} / 2.0")
    print("Churn risk :", f"{answers['churn_risk']['noul']:.1%}")
    print("\nFull result:")
    print(json.dumps(result, indent=2))
    PY
  '';
in
symlinkJoin {
  name = "laya-${version}";
  paths = [
    data
    laya-setup
    laya-python
    laya-mcp
    laya-demo
  ];
  meta = with lib; {
    description = "Laya System 1 decision engine (CLI + streamable-HTTP MCP server)";
    homepage = "https://huggingface.co/convaiinnovations/laya";
    license = licenses.asl20;
    platforms = platforms.linux;
    mainProgram = "laya-mcp";
  };
}
