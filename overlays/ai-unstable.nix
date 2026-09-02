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
  opencode = unstablePkgs.opencode;
  pi-coding-agent = unstablePkgs.pi-coding-agent;
  jetbrains-toolbox = unstablePkgs.jetbrains-toolbox;
  vscode = unstablePkgs.vscode;
}
