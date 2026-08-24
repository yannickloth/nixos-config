{
  description = "Standalone home-manager configs for each family user";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, home-manager }: let
    system = "x86_64-linux";
    pkgs = import nixpkgs {
      inherit system;
      config.allowUnfree = true;
    };
    mkHome = user: home-manager.lib.homeManagerConfiguration {
      inherit pkgs;
      modules = [ ./${user}/${user}-hm.nix ];
    };
  in {
    homeConfigurations = {
      nicky = mkHome "nicky";
      aeiuno = mkHome "aeiuno";
      sven = mkHome "sven";
      aaron = mkHome "aaron";
    };
  };
}
