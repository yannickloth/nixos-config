# home-manager wrapper for the BrowserOS neo package (see ./default.nix).
#
#   imports = [ ../../packages/browseros/home.nix ];
#   browseros.enable = true;
#
# BrowserOS neo is a separate, agent-driven browser that AI assistants connect
# to over MCP. It runs with the user's real logins in its own profile, while
# the main browser stays untouched.
{
  config,
  lib,
  pkgs,
  ...
}:

with lib;

let
  cfg = config.browseros;

  # The upstream agent skill is a single file (skills/browseros-neo/SKILL.md).
  # Fetch exactly that file at a pinned commit: the repo is a Chromium fork, so
  # pulling the tree would be gigabytes. `npx skills add browseros-ai/browseros
  # --skill browseros-neo` writes the same file; this makes it reproducible and
  # survive a `home-manager switch`. Bumping skillRev requires bumping the hash
  # (`nix-prefetch-url <raw url>`).
  skillFile = pkgs.fetchurl {
    url = "https://raw.githubusercontent.com/browseros-ai/browseros/${cfg.skillRev}/skills/browseros-neo/SKILL.md";
    sha256 = "0j1yg58ydana5p8zss7bmswb3rlq2l120rc6z662iv1rm8mpfqdn";
  };

  # Agent skill directories, mirroring packages/rea/home.nix and
  # packages/herdr/home.nix: `~/.agents/skills` is the shared dir OpenCode/Pi
  # read; Claude Code and Hermes Agent have their own.
  skillDirs = [
    ".agents"
    ".claude"
    ".hermes"
  ];

  skillLinks = listToAttrs (
    map (dir: nameValuePair "${dir}/skills/browseros-neo/SKILL.md" {
      source = skillFile;
      # The `skills` CLI may have written a real file here first; replace it so
      # the deployment stays declarative.
      force = true;
    }) skillDirs
  );
in

{
  options.browseros = {
    enable = mkEnableOption "BrowserOS neo (agent-driven browser for AI assistants)";

    package = mkOption {
      type = types.package;
      default = pkgs.browseros;
      defaultText = literalExpression "pkgs.browseros";
      description = "The BrowserOS neo package (packages/browseros/default.nix, via the ai-unstable overlay).";
    };

    installSkill = mkOption {
      type = types.bool;
      default = true;
      description = ''
        Install the upstream agent skill (skills/browseros-neo/SKILL.md) into
        the agent skill directories and into OpenCode's config dir.
      '';
    };

    skillRev = mkOption {
      type = types.str;
      default = "512f9cc15962b00b65b2cb35c429ed3134764f84";
      defaultText = literalExpression ''"512f9cc15962b00b65b2cb35c429ed3134764f84"'';
      description = "Commit of browseros-ai/browseros the skill is taken from.";
    };
  };

  config = mkIf cfg.enable (mkMerge [
    {
      home.packages = [ cfg.package ];

      # BrowserOS ships its own desktop entry and icon in the package
      # (default.nix extraInstallCommands), so no extra MIME configuration is
      # needed here.
    }

    (mkIf cfg.installSkill {
      home.file = skillLinks;

      # OpenCode reads skills from its own config dir as well.
      xdg.configFile."opencode/skills/browseros-neo/SKILL.md".source = skillFile;
    })
  ]);
}
