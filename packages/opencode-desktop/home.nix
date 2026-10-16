# home-manager wrapper for the opencode Desktop package (see ./default.nix).
#
#   imports = [ ../../packages/opencode-desktop/home.nix ];
#   opencode-desktop.enable = true;
#
# The desktop client is the GUI of the opencode v2 line. It shares
# ~/.config/opencode with the `opencode` CLI (users/opencode.nix) — same
# providers, models and plugins — but runs its own bundled agent server, so it
# keeps working regardless of which CLI version is pinned.
{
  config,
  lib,
  pkgs,
  ...
}:

with lib;

let
  cfg = config.opencode-desktop;
in

{
  options.opencode-desktop = {
    enable = mkEnableOption "opencode Desktop (graphical client for the opencode v2 agent)";

    package = mkOption {
      type = types.package;
      default = pkgs.opencode-desktop;
      defaultText = literalExpression "pkgs.opencode-desktop";
      description = "The opencode Desktop package (packages/opencode-desktop/default.nix, via the ai-unstable overlay).";
    };
  };

  config = mkIf cfg.enable {
    home.packages = [ cfg.package ];

    # The desktop entry and icons ship inside the package (default.nix
    # extraInstallCommands). Upstream's entry id is ai.opencode.desktop, and it
    # declares MimeType=x-scheme-handler/opencode — register it as the handler
    # for the opencode:// links the app and web UI hand out.
    xdg.mimeApps.enable = true;
    xdg.mimeApps.defaultApplications."x-scheme-handler/opencode" = [ "ai.opencode.desktop.desktop" ];
  };
}
