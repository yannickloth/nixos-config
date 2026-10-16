# home-manager wrapper for herdr (terminal multiplexer / runtime for coding
# agents, https://herdr.dev). The package itself comes from nixpkgs-unstable via
# the AI-unstable overlay (overlays/ai-unstable.nix) — herdr is in no stable
# channel yet.
#
#   imports = [ ../../packages/herdr/home.nix ];
#   herdr.enable = true;                  # CLI + agent skill + integrations
#   herdr.integrations = [ "opencode" "pi" "hermes" ];
#
# This does the two things herdr otherwise asks the user to run by hand:
#
#   1. The per-agent integrations (`herdr integration install <target>`). They
#      tell herdr which agent session occupies a pane, so it can resume that
#      session after a server restart (`opencode --session <id>`), and — for pi,
#      omp, kimi, opencode, kilo and mastracode — let the agent report its own
#      idle/working/blocked state instead of herdr guessing it from the screen
#      (the rest, hermes included, report only the session to resume). herdr
#      writes those files into the AGENT's own config directory
#      (~/.config/opencode/plugins/..., ~/.pi/agent/extensions/..., ...), which
#      home-manager does not manage, so they are installed from home.activation
#      rather than generated. herdr refuses to install into an agent that has no
#      config directory yet, so the module creates it first — the same directory
#      a first run of that agent would create.
#
#   2. The agent skill (`herdr --skill`), linked into the shared agent skill
#      directories exactly like packages/rea/home.nix links REA's:
#      ~/.agents/skills is read by OpenCode and Pi, ~/.claude and ~/.hermes by
#      Claude Code and Hermes Agent.
{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
let
  cfg = config.herdr;

  # `herdr --skill` prints the skill that is compiled into the binary, so this
  # copy can never drift from the installed version — no upstream tag and hash
  # to bump (unlike packages/orca/home.nix, whose skills are separate files).
  skillDir = pkgs.runCommand "herdr-skill-herdr" { } ''
    mkdir -p $out
    ${getExe cfg.package} --skill > $out/SKILL.md
  '';

  skillAgentDirs = [
    ".agents"
    ".claude"
    ".hermes"
  ];

  skillLinks = listToAttrs (
    concatMap
      (name:
        map (dir: nameValuePair "${dir}/skills/${name}" {
          source = skillDir;
          force = true;
        }) skillAgentDirs)
      cfg.skills
  );

  # Config directory, relative to $HOME, that each integration needs to already
  # exist: herdr's installer fails with "<agent> config directory not found at
  # ...; install <agent> first" otherwise. These are herdr 0.9.x's own
  # resolution rules (docs/versions/*/website/src/content/docs/integrations.mdx
  # upstream) — note `pi` wants the agent dir, not the extensions/ dir below it,
  # which herdr creates itself.
  targetConfigDirs = {
    pi = [ ".pi/agent" ];
    omp = [ ".omp/agent" ];
    claude = [ ".claude" ];
    codex = [ ".codex" ];
    copilot = [ ".copilot" ];
    devin = [ ".config/devin" ];
    droid = [ ".factory" ];
    kimi = [ ".kimi-code" ];
    opencode = [ ".config/opencode" ];
    kilo = [ ".config/kilo" ];
    hermes = [ ".hermes" ];
    qodercli = [ ".qoder" ];
    qwen = [ ".qwen" ];
    cursor = [ ".cursor" ];
    mastracode = [ ".mastracode" ];
    antigravity-cli = [ ".gemini/config" ];
    grok = [ ".grok" ];
    letta = [ ".letta" ];
  };

  # One integration per activation: create its config directory, then install.
  # herdr's installs are idempotent (they rewrite their own files atomically and
  # leave the rest of the agent config alone), so re-running on every switch is
  # what keeps them current after a herdr upgrade — herdr bumps an integration
  # version and expects a reinstall. A failure must not block the switch (the
  # agent may simply not be set up in this home), hence the warning.
  installIntegration = target: ''
    ${concatMapStringsSep "\n" (dir: "$DRY_RUN_CMD mkdir -p \"$HOME/${dir}\"") (targetConfigDirs.${target} or [ ])}
    if ! $DRY_RUN_CMD ${getExe cfg.package} integration install ${target}; then
      echo "herdr: integration install ${target} failed; is ${target} installed for this user?" >&2
    fi
  '';
in
{
  options.herdr = {
    enable = mkEnableOption "herdr (terminal multiplexer and runtime for coding agents)";

    package = mkOption {
      type = types.package;
      default = pkgs.herdr;
      defaultText = literalExpression "pkgs.herdr";
      description = "The herdr package (nixpkgs-unstable, via the ai-unstable overlay).";
    };

    integrations = mkOption {
      type = types.listOf (types.enum (attrNames targetConfigDirs));
      default = [
        "opencode"
        "pi"
        "hermes"
      ];
      example = literalExpression ''[ "opencode" "pi" "hermes" "claude" ]'';
      description = ''
        Agent integrations to install at activation (`herdr integration install
        <target>`), one per coding agent this user actually has. herdr uses them
        to resume an agent's session after a server restart, and — for the
        agents that report state — to show whether a pane is idle, working or
        blocked. `herdr integration status` lists the installed ones.
      '';
    };

    skills = mkOption {
      type = types.listOf (types.enum [ "herdr" ]);
      default = [ "herdr" ];
      example = literalExpression ''[ "herdr" ]'';
      description = ''
        Agent skill guides to install declaratively into the agent skill
        directories (`~/.agents/skills` plus `~/.claude` and `~/.hermes`). The
        file is printed by the packaged binary (`herdr --skill`), so it always
        matches the installed version and needs no network at activation.
      '';
    };
  };

  config = mkIf cfg.enable {
    home.packages = [ cfg.package ];

    # Declarative, offline install of the requested skills (see skillLinks).
    home.file = skillLinks;

    # Runs after the files are written: the agents' config directories (opencode,
    # hermes) may only appear with this generation's home-manager files, and the
    # integrations go into those directories.
    home.activation.herdrIntegrations = mkIf (cfg.integrations != [ ]) (
      lib.hm.dag.entryAfter [ "writeBoundary" ] (concatMapStrings installIntegration cfg.integrations)
    );
  };
}
