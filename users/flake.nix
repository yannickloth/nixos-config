# Standalone home-manager configs for each family user.
#
# Base is stable nixpkgs (nixos-26.05, matching the NixOS hosts' root
# flake.nix). The adults (nicky, aeiuno) additionally get opencode,
# pi-coding-agent, jetbrains-toolbox and vscode overlaid from unstable
# nixpkgs because those move fast (built-in AI features). Kids (sven, aaron)
# stay entirely on stable. See ../overlays/ai-unstable.nix.
{
  description = "Standalone home-manager configs for each family user";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-26.05";
    nixpkgs-unstable.url = "github:nixos/nixpkgs/nixos-unstable";
    home-manager = {
      url = "github:nix-community/home-manager/release-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    agenix.url = "github:ryantm/agenix";
    # Same hermes-agent packaging inputs as the root flake (see
    # packages/hermes-agent).
    pyproject-nix.url = "github:nix-community/pyproject.nix";
    pyproject-nix.inputs.nixpkgs.follows = "nixpkgs-unstable";
    pyproject-build-systems.url = "github:pyproject-nix/build-system-pkgs";
    pyproject-build-systems.inputs.pyproject-nix.follows = "pyproject-nix";
    pyproject-build-systems.inputs.nixpkgs.follows = "nixpkgs-unstable";
    uv2nix.url = "github:pyproject-nix/uv2nix";
    uv2nix.inputs.pyproject-nix.follows = "pyproject-nix";
    uv2nix.inputs.nixpkgs.follows = "nixpkgs-unstable";
  };

  outputs = { self, nixpkgs, nixpkgs-unstable, home-manager, agenix, uv2nix, pyproject-nix, pyproject-build-systems }:
    let
      system = "x86_64-linux";
      stablePkgs = import nixpkgs {
        inherit system;
        config.allowUnfree = true;
      };
      unstablePkgs = import nixpkgs-unstable {
        inherit system;
        config.allowUnfree = true;
      };
      hermesAgent = unstablePkgs.callPackage ../packages/hermes-agent {
        inherit uv2nix pyproject-nix pyproject-build-systems;
      };
      aiOverlay = import ../overlays/ai-unstable.nix {
        inherit unstablePkgs;
        inherit hermesAgent;
      };
      # Adults: stable base with the fast-moving AI tooling pulled from unstable.
      adultPkgs = stablePkgs.extend aiOverlay;
      # hostName is passed so host-specific bits (e.g. Unsloth on laptop-p16) can
      # be gated at build time via commonHm.hostName (config.networking.hostName
      # does not exist in standalone home-manager). See nicky-hm.nix isP16.
      mkHome = user: hostName: userPkgs: home-manager.lib.homeManagerConfiguration {
        pkgs = userPkgs;
        modules = [
          agenix.homeManagerModules.default
          ./${user}/${user}-hm.nix
          { commonHm.hostName = hostName; }
        ];
      };
    in
    {
      homeConfigurations = {
        # Default targets. nicky is deployed on laptop-p16 (CachyOS).
        nicky = mkHome "nicky" "laptop-p16" adultPkgs;
        aeiuno = mkHome "aeiuno" "laptop-p16" adultPkgs;
        sven = mkHome "sven" "laptop-p16" stablePkgs;
        aaron = mkHome "aaron" "laptop-p16" stablePkgs;
      };
    };
}
