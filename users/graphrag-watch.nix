{
  config,
  lib,
  pkgs,
  ...
}:

# Standalone change detector for GraphRAG indexes.
#
# The opencode plugin records the edits it sees itself (its own write/edit tools,
# plus whatever its file watcher notices). This user timer covers the rest: it
# finds every `<repo>/<indexRoot>/manifest.json` under the configured roots and
# reconciles each repository with git, so work done in another harness (pi), in
# an IDE, or by a script still marks content dirty.
#
# It never indexes. The next opencode idle, or an explicit `graphrag mode=index`,
# still decides, with the plugin's preflight and completion gate.
#
# Keyed on manifest discovery, not on a list of project paths: renaming, moving,
# adding or removing a checkout — including a worktree — needs no configuration
# change. Worktrees are separate projects because each carries its own manifest.

let
  cfg = config.graphragWatch;
  home = config.home.homeDirectory;
  reconcile = "${cfg.pluginDir}/graphrag/opencode/reconcile.ts";
  roots = lib.concatStringsSep "," cfg.roots;
in
{
  options.graphragWatch = {
    enable = lib.mkEnableOption "the GraphRAG change detector";

    roots = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "${home}/code" ];
      description = "Directories scanned for <repo>/<indexRoot>/manifest.json.";
    };

    indexRoot = lib.mkOption {
      type = lib.types.str;
      default = "graph-index";
      description = ''
        Index directory name inside a project. Must match `index_root` in the
        plugin's config/graphrag.yaml.
      '';
    };

    maxDepth = lib.mkOption {
      type = lib.types.int;
      default = 5;
      description = "How many directory levels below each root to scan.";
    };

    interval = lib.mkOption {
      type = lib.types.str;
      default = "5min";
      description = "Reconciliation period (systemd OnUnitActiveSec).";
    };

    pluginDir = lib.mkOption {
      type = lib.types.str;
      default = "${home}/code/llm-harness-plugins";
      description = "Checkout containing graphrag/opencode/reconcile.ts.";
    };
  };

  config = lib.mkIf cfg.enable {
    # No `builtins.pathExists` assertion here: flake evaluation is pure, so a
    # checkout outside the store is not readable and the assertion would always
    # fail. A missing script surfaces as a failed unit in `journalctl --user`.

    systemd.user.services.graphrag-watch = {
      Unit.Description = "Reconcile GraphRAG indexes with git";
      Service = {
        Type = "oneshot";
        ExecStart = "${pkgs.bun}/bin/bun ${reconcile} --roots ${roots} --index-root ${cfg.indexRoot} --max-depth ${toString cfg.maxDepth}";
        Nice = 10;
      };
    };

    systemd.user.timers.graphrag-watch = {
      Unit.Description = "Periodic GraphRAG index reconciliation";
      Timer = {
        OnBootSec = "2min";
        OnUnitActiveSec = cfg.interval;
        Persistent = true;
      };
      Install.WantedBy = [ "timers.target" ];
    };
  };
}
