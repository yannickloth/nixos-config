# Open Code Review (alibaba/open-code-review, https://open-codereview.ai) —
# Alibaba's AI code-review CLI (`ocr`): reads git diffs, sends them to a
# configurable OpenAI/Anthropic-compatible LLM through an agent with tool use
# plus deterministic pipelines, and returns line-level review comments.
#
# NOT an LLM API itself: open-codereview.ai serves no chat-completions
# endpoint (verified 2026-10-21: /v1/models 404, /v1/chat/completions 405 —
# an earlier attempt had added it as an opencode *provider*, which could
# never work). `ocr` consumes the LLM endpoints configured via
# `ocr config provider` (user-local, keys stay out of the repo), or runs in
# delegation mode where the calling coding agent's own model does the LLM
# work. The OpenCode integration (ocr_review tool + /ocr-review slash
# commands) is packaged alongside in plugin-deps.nix and deployed by
# users/opencode.nix.
#
# Not in nixpkgs, so it is packaged in-tree from the upstream source, like
# magpie. Upstream also publishes prebuilt release binaries and an npm
# wrapper that downloads them at install time — both unusable in a Nix build,
# hence the source build.
{ lib
, buildGoModule
, fetchFromGitHub
}:

buildGoModule rec {
  pname = "open-code-review";
  version = "1.13.2";

  src = fetchFromGitHub {
    owner = "alibaba";
    repo = "open-code-review";
    rev = "v${version}";
    hash = "sha256-/ov2RIiZwbT7Pn9+lzvGBoOrjvGhW1asgKPf1kQUweQ=";
  };

  vendorHash = "sha256-LpqnNp6gxHatHH68pM59ESQICDDSVrkZm7AJLVvYTao=";

  # The pinned nixpkgs-unstable (users/flake.lock rev 151fa4e8) ships Go
  # 1.26.8; upstream's go.mod demands 1.26.9 — a patch release that adds no
  # language features, so relax the directive. Drop this once nixpkgs-unstable
  # carries Go >= 1.26.9.
  postPatch = ''
    substituteInPlace go.mod --replace-fail "go 1.26.9" "go 1.26.8"
  '';

  # Only the CLI. `./...` would also build internal/llm/gen (a codegen tool)
  # and the acp/ mock servers (mock-ocr, ocr-stub).
  subPackages = [ "cmd/opencodereview" ];

  # Upstream installs the binary as `ocr` (install.sh BIN, npm bin), not as
  # the cmd/ directory name. ldflags stamp main.Version (fed to llm.AppVersion;
  # otherwise `ocr version` reports "dev").
  ldflags = [
    "-s"
    "-w"
    "-X"
    "main.Version=${version}"
  ];
  postInstall = ''
    mv $out/bin/opencodereview $out/bin/ocr
  '';

  # The suite is not hermetic: it expects git repositories with history and
  # live LLM endpoints, so it cannot run in the build sandbox.
  doCheck = false;

  meta = with lib; {
    description = "Open Code Review (ocr): Alibaba's AI code-review CLI over your own LLM";
    homepage = "https://open-codereview.ai";
    license = licenses.asl20;
    mainProgram = "ocr";
    platforms = platforms.linux;
  };
}
