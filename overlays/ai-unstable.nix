# Overlay that swaps the fast-moving, AI-heavy tooling to unstable nixpkgs
# builds. Applied per-user (nicky, aeiuno) by both the root flake's
# home-manager module and the standalone users/flake.nix, so every host gives
# the adults bleeding-edge AI tooling while kids stay on stable nixpkgs.
#
# Example: the opencode / pi-coding-agent / jetbrains-toolbox / vscode you get
# on a stable channel lag unstable by weeks-to-months. These four move fast
# because of built-in AI features, so they are pulled from nixos-unstable.
{ unstablePkgs }:

final: prev: {
  # opencode 1.18.30/1.18.31 crash on every prompt when the config declares
  # any custom provider: "TypeError: undefined is not an object (evaluating
  # 'a.name')" / "Unexpected server error". Root cause is a circular runtime
  # import between packages/core/src/filesystem.ts and
  # filesystem/search.ts, which the newer Bun bundler (1.4.x, now used by
  # nixpkgs) evaluates in the order that leaves FileSystemSearch.node
  # undefined. Upstream fixed it in anomalyco/opencode PR #49298 (merged to
  # dev 2026-09-16), but as of 1.18.31 no tagged release contains the fix.
  # Apply that patch until a release with it lands in nixpkgs-unstable, then
  # drop it. See packages/patches/.
  opencode = (unstablePkgs.opencode.overrideAttrs (old: {
    patches = (old.patches or [ ]) ++ [
      ../packages/patches/opencode-fix-filesystem-import-cycle.patch
    ];
  }));
  pi-coding-agent = unstablePkgs.pi-coding-agent;
  jetbrains-toolbox = unstablePkgs.jetbrains-toolbox;
  vscode = unstablePkgs.vscode;
}
