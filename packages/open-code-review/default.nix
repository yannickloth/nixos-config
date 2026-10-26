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
  version = "1.13.3";

  src = fetchFromGitHub {
    owner = "alibaba";
    repo = "open-code-review";
    rev = "v${version}";
    hash = "sha256-dDKNxjI0pWoJGabUvsGTERYKvKtvEm3UGD/FLPKpfnw=";
  };

  vendorHash = "sha256-LpqnNp6gxHatHH68pM59ESQICDDSVrkZm7AJLVvYTao=";

  # The pinned nixpkgs-unstable carries Go 1.26.10, which satisfies upstream's
  # `go 1.26.9` directive, so go.mod is used as shipped (the 1.26.9 -> 1.26.8
  # relax needed by the 1.13.2-era pin is gone).
  # Upstream embeds its extension allowlist (internal/config/allowlist/
  # supported_file_types.json) and its path-to-rule map into the binary with
  # //go:embed, so markdown cannot be enabled at run time — `ocr review
  # --preview` reports every .md file as `unsupported_ext`. Upstream main still
  # ships no markdown (checked 2026-10-25, v1.13.3 included), so it is patched
  # in here. Markdown carries the skills, agent prompts, and AGENTS.md files
  # that drive every other artifact in these repos; reviewing them is the point.
  postPatch = ''
    # Enable the extensions: append to the embedded allowlist array.
    substituteInPlace internal/config/allowlist/supported_file_types.json \
      --replace-fail '".metal"' '".metal", ".md", ".markdown"'

    # Map them to an instruction-file rule. First match wins, and json.md is
    # keyed on file extension alone, so the markdown entries stay ahead of it.
    substituteInPlace internal/config/rules/system_rules.json \
      --replace-fail '"path_rule_map": {' \
        '"path_rule_map": { "**/*.md": "markdown.md", "**/*.markdown": "markdown.md",'

    # rule_docs/ is //go:embed-ed with a glob, so a new document joins it.
    cat > internal/config/rules/rule_docs/markdown.md <<'MARKDOWN_RULES'
#### Instruction integrity

- Every file path, command, agent name, skill name, and section heading this
  file cites must exist in this repository. A citation to a file that does not
  exist is blocking: the reader is an agent that will follow the text literally.
- Frontmatter keys must be valid for their consumer — `mode`, `name`,
  `description`, `permission`, `model` for agent files; `name`, `description`,
  `compatibility` for skill files. An unrecognised key is silently ignored, so
  a misplaced setting never takes effect.
- A cross-reference to another step, phase, or rule must resolve. "See Step 5"
  must name a step that exists after any renumbering.

#### Executability

- Every command must run as written: correct interpreter, correct working
  directory, arguments in the order the tool accepts them.
- An instruction whose outcome cannot be observed by running something must say
  how the reader confirms it.
- An ordering constraint must be explicit. Two steps whose order matters, and
  which do not say so, are a defect.

#### Contradictions and gaps

- Flag two instructions that cannot both be satisfied.
- Flag a rule stated twice in different words, and a rule stated once and then
  never applied.
- Flag a claimed count (files, steps, items) that the repository contradicts.
  Counts read from the data are preferred over counts written in prose.
- Flag a gate that no tool enforces and that the text does not ask a person to
  check.

#### Agent and permission correctness

- A file declaring `mode: subagent` must not be presented as a primary agent,
  and a file that audits or reports must deny `edit` and `write`.
- A read-only auditor that can write is a defect: it will change the artifact it
  is judging.
- A skill must not depend on an agent that does not exist.

#### Scope and duplication

- Flag a restatement of another file's rules where the two copies can drift;
  cite the other file instead.
- Flag instructions that reach outside the declared scope of this file.
MARKDOWN_RULES
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
