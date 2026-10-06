# Overlay that swaps the fast-moving, AI-heavy tooling to unstable nixpkgs
# builds. Applied per-user (nicky, aeiuno) by both the root flake's
# home-manager module and the standalone users/flake.nix, so every host gives
# the adults bleeding-edge AI tooling while kids stay on stable nixpkgs.
#
# Example: the opencode / pi-coding-agent / jetbrains-toolbox / vscode you get
# on a stable channel lag unstable by weeks-to-months. These move fast because
# of built-in AI features, so they are pulled from nixos-unstable. hermes-agent,
# magpie and deepseek-harness are not in nixpkgs at all and are packaged in-tree
# (packages/hermes-agent, packages/magpie, packages/deepseek-harness).
{ unstablePkgs, hermesAgent }:

final: prev: {
  # opencode 1.18.30/1.18.31 crashed on every prompt when the config declared
  # any custom provider: "TypeError: undefined is not an object (evaluating
  # 'a.name')" / "Unexpected server error". Root cause was a circular runtime
  # import between packages/core/src/filesystem.ts and filesystem/search.ts,
  # which the newer Bun bundler (1.4.x) evaluated in the order that left
  # FileSystemSearch.node undefined. Upstream fixed it in anomalyco/opencode
  # PR #49298 (v1.18.32), and nixpkgs-unstable now ships 1.18.34, so the
  # in-tree patch was dropped (see git history / packages/patches).
  opencode = unstablePkgs.opencode;
  pi-coding-agent = unstablePkgs.pi-coding-agent;
  # Hermes Agent is packaged in-tree (packages/hermes-agent) from upstream's
  # uv.lock via uv2nix — it is not in nixpkgs at all.
  hermes-agent = hermesAgent;
  # magpie (yetone/magpie): menu-bar/TUI/CLI model switcher and the local
  # gateway every agent points at. Packaged in-tree (packages/magpie) and built
  # with unstable's Go, which go.mod requires (>= 1.26.3).
  magpie = unstablePkgs.callPackage ../packages/magpie { };
  # DeepSeek Harness (dsh): agent harness published only on npm, packaged
  # in-tree from the registry tarball (packages/deepseek-harness).
  deepseek-harness = unstablePkgs.callPackage ../packages/deepseek-harness { };
  # Orca (ADE): not in nixpkgs and only shipped as a prebuilt Electron AppImage,
  # wrapped as a normal derivation in packages/orca. Exposed here so the adults
  # (nicky, aeiuno) get `pkgs.orca` on every host.
  orca = unstablePkgs.callPackage ../packages/orca { };
  jetbrains-toolbox = unstablePkgs.jetbrains-toolbox;
  vscode = unstablePkgs.vscode;
}
