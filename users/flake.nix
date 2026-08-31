{
  description = "Standalone home-manager configs for each family user";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    agenix.url = "github:ryantm/agenix";
  };

  outputs = { self, nixpkgs, home-manager, agenix }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs {
        inherit system;
        config.allowUnfree = true;
      };
      # hostName is passed so host-specific bits (e.g. Unsloth on laptop-p16) can
      # be gated at build time via commonHm.hostName (config.networking.hostName
      # does not exist in standalone home-manager). See nicky-hm.nix isP16.
      mkHome = user: hostName: home-manager.lib.homeManagerConfiguration {
        inherit pkgs;
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
        nicky = mkHome "nicky" "laptop-p16";
        aeiuno = mkHome "aeiuno" "laptop-p16";
        sven = mkHome "sven" "laptop-p16";
        aaron = mkHome "aaron" "laptop-p16";
      };
    };
}
