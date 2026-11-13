# home-manager wrapper for the REA package (see ./default.nix).
#
#   imports = [ ../../packages/rea/home.nix ];
#   rea.enable = true;
#
# Installs the `rea` CLI/MCP server and the agent skill that teaches an agent
# how to drive it ("reverse-engineer-anything"). REA's own `npx rea-agents setup`
# installs the skill imperatively (network + writes outside the store); here we
# link the copy that already ships inside the pinned npm tarball, so the skill
# always matches the packaged version and needs no network at activation.
{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
let
  cfg = config.rea;

  # The published tarball carries the skill at skills/<name>/ (SKILL.md plus a
  # references/ directory). Copy each into its own store directory so every
  # install target is a single symlink, the same shape `npx skills add` makes.
  skillDir = name: pkgs.runCommand "rea-skill-${name}" { } ''
    cp -r ${cfg.package}/lib/node_modules/rea-agents/skills/${name} $out
    chmod -R u+w $out
  '';

  # `~/.agents/skills` is the shared dir OpenCode/Cline/Pi read; Claude Code and
  # Hermes Agent get their own `skills/` (mirrors packages/orca/home.nix).
  skillAgentDirs = [
    ".agents"
    ".claude"
    ".hermes"
  ];

  skillLinks = listToAttrs (
    concatMap
      (name:
        map (dir: nameValuePair "${dir}/skills/${name}" {
          source = skillDir name;
          # No force: force makes home-manager rm -rf whatever is at the path
          # (a hand-installed skill dir included). Without it the link is still
          # replaced, and a real directory makes the switch fail loudly instead
          # of being destroyed.
        }) skillAgentDirs)
      cfg.skills
  );
in
{
  options.rea = {
    enable = mkEnableOption "REA (reverse-engineering MCP server + CLI) and its agent skill";

    package = mkOption {
      type = types.package;
      default = pkgs.rea;
      defaultText = literalExpression "pkgs.rea";
      description = "The REA package (packages/rea/default.nix, via the ai-unstable overlay).";
    };

    skills = mkOption {
      type = types.listOf (types.enum [ "reverse-engineer-anything" ]);
      default = [ "reverse-engineer-anything" ];
      example = literalExpression ''[ "reverse-engineer-anything" ]'';
      description = ''
        REA skill guides to install declaratively into the agent skill
        directories (`~/.agents/skills` plus `~/.claude` and `~/.hermes`).
        Taken from the packaged tarball, so no network or `npx` at activation.
      '';
    };
  };

  config = mkIf cfg.enable {
    home.packages = [ cfg.package ];
    home.file = skillLinks;
  };
}
