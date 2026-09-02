# Applied by each NixOS host (via the root flake). Gives nicky and aeiuno the
# AI-unstable overlay (opencode, pi-coding-agent, jetbrains-toolbox, vscode)
# on top of the host's stable pkgs, while sven/aaron keep plain stable pkgs.
#
# This mirrors what the standalone users/flake.nix does by passing per-user
# pkgs to homeManagerConfiguration: it overrides the home-manager per-user
# `pkgs` module argument (seeded with the system pkgs via mkDefault, hence the
# mkForce), the same mechanism home-manager's own tests use.
{ config, lib, pkgs, aiOverlay, ... }:

with lib;

{
  home-manager.users.nicky._module.args.pkgs = mkForce (pkgs.extend aiOverlay);
  home-manager.users.aeiuno._module.args.pkgs = mkForce (pkgs.extend aiOverlay);
}
