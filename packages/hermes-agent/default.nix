# hermes-agent (Nous Research) — packaged from upstream's uv.lock via uv2nix.
# The project exact-pins every dependency (supply-chain hardening), so a
# hand-written python3Packages expression would rot immediately; building the
# virtualenv from the locked PyPI set keeps the pins exact and reviewable.
#
# Extras are installed eagerly from the lock (lazy pip installs cannot work
# against the read-only Nix store). The Chinese enterprise-messaging extras
# (dingtalk, feishu) are excluded deliberately — everything general-purpose
# (MCP, dashboard, google, messaging, voice, wake, ...) is in.
#
# kittentts is excluded too: it is the only extra that reaches the GPU stack
# (kittentts -> spacy -> spacy-curated-transformers -> torch -> triton ->
# nvidia-*), and those PyPI CUDA wheels (a CUDA-12/13 mix whose libs live in
# non-standard site-packages/nvidia/*/lib dirs) fail uv2nix's auto-patchelf
# ("could not satisfy libcublas.so.13"). The previous pin (2026.9.14) had no
# kittentts and no torch at all, so dropping it restores that dependency
# surface and keeps the closure ~6 GiB smaller. Re-include it only together
# with CUDA overrides that add nixpkgs cudaPackages.libcublas/libcusparse/
# libnvjitlink to the corresponding nvidia-* wheels' nativeBuildInputs.
# See https://discourse.nixos.org/t/72028.
{
  lib,
  stdenv,
  makeWrapper,
  callPackage,
  python314,
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
  # Pin: v0.22.2 (2026-10-15).
  src = fetchFromGitHub {
    owner = "NousResearch";
    repo = "hermes-agent";
    rev = "d923a5eb487a17c0a68801bba9ef0f56c81040a8";
    hash = "sha256-i9rob9jtBv6XTV0acNbHDEUM+9f3ZsN1zJkD6dMBzTc=";
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
    # Several upstream sdists use setuptools as their build backend but omit it
    # from build-system.requires, so uv2nix's build environment lacks it. Provide
    # it explicitly for the affected packages.
    pilk = prev.pilk.overrideAttrs (old: {
      nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ (final.resolveBuildSystem { setuptools = [ ]; });
    });
    python-olm = prev.python-olm.overrideAttrs (old: {
      nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ (final.resolveBuildSystem { setuptools = [ ]; });
    });
  };

  # requires-python = ">=3.11,<3.15", but the pinned release's uv.lock narrows
  # the resolution to supported-markers = ["python_full_version >= '3.14'"], and
  # uv2nix asserts the build environment satisfies one of them — so the base
  # interpreter must be 3.14. (The old 3.11 pin existed only for tflite-runtime's
  # cp311-only wheels; upstream dropped tflite-runtime from the lock.)
  pythonSet =
    (callPackage pyproject-nix.build.packages { python = python314; }).overrideScope (
      lib.composeManyExtensions [
        pyproject-build-systems.overlays.wheel
        pyprojectOverlay
        pyprojectOverrides
      ]
    );

  depsSelection = workspace.deps.all // {
    hermes-agent = lib.subtractLists [ "dingtalk" "feishu" "kittentts" ] workspace.deps.all.hermes-agent;
  };

  virtualenv = pythonSet.mkVirtualEnv "hermes-agent-env" depsSelection;
in
stdenv.mkDerivation {
  pname = "hermes-agent";
  version = "0.22.2";

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
