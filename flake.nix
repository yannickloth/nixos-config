{
  description = "NixOS configuration";

  # Binary caches to use for this flake's dependencies. Important for the
  # CachyOS kernel: its own flake's nixConfig is NOT honored when it's an
  # input, so the Attic cache must be declared here (and in nix.settings).
  nixConfig = {
    extra-substituters = [ "https://attic.xuyh0120.win/lantian" ];
    extra-trusted-public-keys = [ "lantian:EeAUQ+W+6r7EtwnmYjeVwx5kOGEBpjlBfPlzGlTNvHc=" ];
  };

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-26.05";
    home-manager.url = "github:nix-community/home-manager/release-26.05";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";
    nixos-hardware.url = "github:NixOS/nixos-hardware/master";
    # CachyOS kernel: tracks the moving `release` branch (deliberate "latest"
    # choice for all hosts, consistent with system.nixos.versionSuffix = ".latest").
    # For reproducibility, pin to a specific tag/rev here; otherwise `nix flake
    # update` advances the kernel. The kernel binary cache is declared above in
    # nixConfig (and in roles/nix.nix) because the CachyOS flake's own nixConfig
    # is NOT honored when used as an input.
    nix-cachyos-kernel.url = "github:xddxdd/nix-cachyos-kernel/release";
  };

  outputs = inputs@{ self, nixpkgs, home-manager, nixos-hardware, nix-cachyos-kernel, ... }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs {
        inherit system;
        config.allowUnfree = true;
      };
    in
    {
      devShells.${system}.default = pkgs.mkShell {
        packages = with pkgs; [
          nixpkgs-fmt
          nil
          nix-output-monitor
          nvd
          rage
          git
          jq
          ripgrep
          fd
          bat
          eza
          direnv
          shellcheck
        ];
      };

      nixosConfigurations =
        let
          cachyos-bore-lto = { pkgs, ... }: {
            nixpkgs.overlays = [ nix-cachyos-kernel.overlays.pinned ];
            boot.kernelPackages = pkgs.cachyosKernels.linuxPackages-cachyos-bore-lto-x86_64-v3;
          };
        in
        {
          laptop-hera = nixpkgs.lib.nixosSystem {
            system = "x86_64-linux";
            modules = [
              ./hosts/laptop-hera/laptop-hera-configuration.nix
              home-manager.nixosModules.home-manager
              {
                home-manager.useGlobalPkgs = true;
                home-manager.useUserPackages = true;
                #home-manager.users.jdoe = import ./home.nix;

                # Optionally, use home-manager.extraSpecialArgs to pass
                # arguments to home.nix
              }
              # TODO: enable a specific Dell XPS module once the exact model is
              # confirmed on the physical machine (e.g. `sudo dmidecode -s system-product-name`).
              # Likely candidates: dell-xps-13-9360 (same as laptop-xps), 9300, 9310.
              #           nixos-hardware.nixosModules.dell-xps-13-9360
              cachyos-bore-lto
            ];
          };
          laptop-p16 = nixpkgs.lib.nixosSystem {
            system = "x86_64-linux";
            modules = [
              ./hosts/laptop-p16/laptop-p16-configuration.nix
              home-manager.nixosModules.home-manager
              {
                home-manager.useGlobalPkgs = true;
                home-manager.useUserPackages = true;
                #home-manager.users.jdoe = import ./home.nix;

                # Optionally, use home-manager.extraSpecialArgs to pass
                # arguments to home.nix
              }
              nixos-hardware.nixosModules.lenovo-thinkpad # generic ThinkPad base; a model-specific module (e.g. thinkpad/p16s) may be added once confirmed via dmidecode
              cachyos-bore-lto
            ];
          };
          laptop-xps = nixpkgs.lib.nixosSystem {
            system = "x86_64-linux";
            modules = [
              ./hosts/laptop-xps/laptop-xps-configuration.nix
              home-manager.nixosModules.home-manager
              {
                home-manager.useGlobalPkgs = true;
                home-manager.useUserPackages = true;
                #home-manager.users.jdoe = import ./home.nix;

                # Optionally, use home-manager.extraSpecialArgs to pass
                # arguments to home.nix
              }

              nixos-hardware.nixosModules.dell-xps-13-9360

              cachyos-bore-lto
            ];
          };
        };
    };
}
