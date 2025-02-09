{
  description = "NixOS configuration";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    home-manager.url = "github:nix-community/home-manager";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";
    nixos-hardware.url = "github:NixOS/nixos-hardware/master";
  };

  outputs = inputs@{ self, nixpkgs, home-manager, nixos-hardware,... }: {
    nixosConfigurations = {
      laptop-hera = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          ./laptop-hera-configuration.nix
          home-manager.nixosModules.home-manager
          {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            #home-manager.users.jdoe = import ./home.nix;

            # Optionally, use home-manager.extraSpecialArgs to pass
            # arguments to home.nix
          }
#           nixos-hardware.nixosModules.dell-xps-13-9360 # TODO check which module may be imported for this laptop
        ];
      };
      laptop-p16 = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          ./laptop-p16-configuration.nix
          home-manager.nixosModules.home-manager
          {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            #home-manager.users.jdoe = import ./home.nix;

            # Optionally, use home-manager.extraSpecialArgs to pass
            # arguments to home.nix
          }
#           nixos-hardware.nixosModules.dell-xps-13-9360 # TODO check which module may be imported for this laptop
        ];
      };
      laptop-xps = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          ./laptop-xps-configuration.nix
          home-manager.nixosModules.home-manager
          {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            #home-manager.users.jdoe = import ./home.nix;

            # Optionally, use home-manager.extraSpecialArgs to pass
            # arguments to home.nix
          }
          
          nixos-hardware.nixosModules.dell-xps-13-9360
        ];
      };
    };
  };
}
