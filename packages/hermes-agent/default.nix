# hermes-agent (Nous Research) — packaged from upstream's uv.lock via uv2nix.
# The project exact-pins every dependency (supply-chain hardening), so a
# hand-written python3Packages expression would rot immediately; building the
# virtualenv from the locked PyPI set keeps the pins exact and reviewable.
#
# Extras are installed eagerly from the lock (lazy pip installs cannot work
# against the read-only Nix store). The Chinese enterprise-messaging extras
# (dingtalk, feishu) are excluded deliberately — everything general-purpose
# (MCP, dashboard, google, messaging, voice, wake, ...) is in.
{
  lib,
  stdenv,
  makeWrapper,
  callPackage,
  python311,
  fetchFromGitHub,
  git,
  ripgrep,
  ffmpeg,
  onnxruntime,
  uv2nix,
  pyproject-nix,
  pyproject-build-systems,
}:

let
  # Pin: v2026.9.14 (2026-09-16).
  src = fetchFromGitHub {
    owner = "NousResearch";
    repo = "hermes-agent";
    rev = "4e9d3c713a3e3d47319ab18a8d8dfade5665270d";
    hash = "sha256-WrBjTVGiNA9eud2EPK6SjDvsML0PO2PhhpqX4QloZm4=";
  };

  workspace = uv2nix.lib.workspace.loadWorkspace { workspaceRoot = src; };

  # Prefer prebuilt manylinux wheels; a handful of sdists still build via
  # pyproject-build-systems.
  pyprojectOverlay = workspace.mkPyprojectOverlay { sourcePreference = "wheel"; };

  # Upstream's setup.py refuses plain wheel builds ("Hermes is distributed via
  # the shell installer, Docker image, or Nix") and expects packagers to set
  # HERMES_NIX_BUILD=1 — the Nix path it documents for uv2nix builds.
  pyprojectOverrides = final: prev: {
    hermes-agent = prev.hermes-agent.overrideAttrs (old: {
      env = (old.env or { }) // {
        HERMES_NIX_BUILD = "1";
      };
    });
    # The manylinux wheel bundles most native libs but expects a system
    # libonnxruntime.so (it does not ship one).
    sherpa-onnx = prev.sherpa-onnx.overrideAttrs (old: {
      buildInputs = (old.buildInputs or [ ]) ++ [ onnxruntime ];
    });
  };

  # requires-python = ">=3.11,<3.14"; also tflite-runtime only publishes
  # cp311 wheels, so the base interpreter must stay on 3.11 (the project's
  # floor) for the wake-word extra.
  pythonSet =
    (callPackage pyproject-nix.build.packages { python = python311; }).overrideScope (
      lib.composeManyExtensions [
        pyproject-build-systems.overlays.wheel
        pyprojectOverlay
        pyprojectOverrides
      ]
    );

  depsSelection = workspace.deps.all // {
    hermes-agent = lib.subtractLists [ "dingtalk" "feishu" ] workspace.deps.all.hermes-agent;
  };

  virtualenv = pythonSet.mkVirtualEnv "hermes-agent-env" depsSelection;
in
stdenv.mkDerivation {
  pname = "hermes-agent";
  version = "0.21.3";

  dontUnpack = true;
  dontBuild = true;
  nativeBuildInputs = [ makeWrapper ];

  installPhase = ''
    runHook preInstall
    mkdir -p $out/bin
    for f in hermes hermes-agent hermes-acp; do
      makeWrapper ${virtualenv}/bin/$f $out/bin/$f \
        --prefix PATH : ${
          lib.makeBinPath [
            git
            ripgrep
            ffmpeg
          ]
        }
    done
    runHook postInstall
  '';

  meta = with lib; {
    description = "The self-improving AI agent by Nous Research";
    homepage = "https://hermes-agent.nousresearch.com/";
    license = licenses.mit;
    mainProgram = "hermes";
    platforms = platforms.linux;
  };
}
