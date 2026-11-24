# Applied by each NixOS host (via the root flake). Gives EVERY family account —
# the adults and the kids — the AI-unstable overlay (opencode, opencode-desktop,
# pi-coding-agent, herdr, jetbrains-toolbox, vscode, hermes-agent, magpie,
# deepseek-harness) on top of the host's stable pkgs. sven and aaron learn to
# code (racket, python3, the JetBrains IDEs: users/kid-hm.nix) with the same
# tooling as their parents, so the kids are on the overlay too.
#
# One list, one generated line per account: hand-written per-user lines are how
# this drifted before (sven had a line, aaron did not, while this file's own
# header claimed both kids stayed on plain stable). Add a family account to
# `overlayUsers` and its override is generated; drop one and it disappears.
#
# Mechanism: this mirrors what the standalone users/flake.nix does by passing
# per-user pkgs to homeManagerConfiguration — it overrides the home-manager
# per-user `pkgs` module argument (seeded with the system pkgs via mkDefault,
# hence the mkForce), the same mechanism home-manager's own tests use.
#
# DO NOT read `config` here. `home-manager.users.<name>._module.args.pkgs` is a
# *submodule argument*: home-manager builds each user's module args from the
# whole config, so probing `config.users.users` (the obvious way to skip
# accounts a host does not define) closes the cycle — it fails as "infinite
# recursion encountered" while evaluating this module's `config`. Keep this
# module config-free: every NixOS host in the flake imports
# users/{nicky,aeiuno,sven,aaron}/*.nix, so all four names always exist.
{
  lib,
  pkgs,
  aiOverlay,
  ...
}:

with lib;

let
  overlayUsers = [
    "nicky"
    "aeiuno"
    "sven"
    "aaron"
  ];
in
{
  config = mkMerge (
    map
      (
        u: {
          home-manager.users.${u}._module.args.pkgs = mkForce (pkgs.extend aiOverlay);
        }
      )
      overlayUsers
  );
}
