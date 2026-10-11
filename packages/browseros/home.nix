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
  };

  config = mkIf cfg.enable {
    home.packages = [ cfg.package ];

    # BrowserOS ships its own desktop entry and icon in the package
    # (default.nix extraInstallCommands), so no extra MIME configuration is
    # needed here.
  };
}
