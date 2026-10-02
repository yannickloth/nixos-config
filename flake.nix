{
  description = "NixOS configuration";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-26.05";
    # Fast-moving AI tooling (opencode, pi-coding-agent, jetbrains-toolbox,
    # vscode) for nicky/aeiuno is overlaid from unstable on top of the stable
    # base; see overlays/ai-unstable.nix.
    nixpkgs-unstable.url = "github:nixos/nixpkgs/nixos-unstable";
    home-manager.url = "github:nix-community/home-manager/release-26.05";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";
    nixos-hardware.url = "github:NixOS/nixos-hardware/master";
    # agenix: age-encrypted secrets managed in git. Encrypted .age files are
    # committed; private keys stay in the gitignored age-keys/ and on each host.
    agenix.url = "github:ryantm/agenix";
    # Strata fork (github.com/yannickloth/forks-Strata), branch perf/am47:
    # upstream 0.1.35 (d9ab843) plus the native-embedding error report and the
    # A3000 bench harness. A flake input (rather than an inline builtins.fetchGit
    # rev) so `nix flake update forksStrata` moves it to the branch head;
    # flake.lock pins the exact rev between updates. The repo ships no flake.nix,
    # so it is consumed as a plain source (`flake = false`). Private repo:
    # fetched over ssh with the invoking user's key. Passed to packages/strata as
    # `strataSrc`.
    forksStrata.url = "git+ssh://git@github.com/yannickloth/forks-Strata.git?ref=refs/heads/perf/am47";
    forksStrata.flake = false;
    # hermes-agent packaging (packages/hermes-agent): builds the upstream
    # uv.lock into a Python virtualenv. Pin all three to this repo's
    # nixpkgs-unstable so there is a single evaluation of nixpkgs.
    pyproject-nix.url = "github:nix-community/pyproject.nix";
    pyproject-nix.inputs.nixpkgs.follows = "nixpkgs-unstable";
    pyproject-build-systems.url = "github:pyproject-nix/build-system-pkgs";
    pyproject-build-systems.inputs.pyproject-nix.follows = "pyproject-nix";
    pyproject-build-systems.inputs.uv2nix.follows = "uv2nix";
    pyproject-build-systems.inputs.nixpkgs.follows = "nixpkgs-unstable";
    uv2nix.url = "github:pyproject-nix/uv2nix";
    uv2nix.inputs.pyproject-nix.follows = "pyproject-nix";
    uv2nix.inputs.nixpkgs.follows = "nixpkgs-unstable";
  };

  outputs = inputs@{ self, nixpkgs, nixpkgs-unstable, home-manager, nixos-hardware, agenix, uv2nix, pyproject-nix, pyproject-build-systems, forksStrata, ... }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs {
        inherit system;
        config.allowUnfree = true;
      };
      # Stable pkgs (nixpkgs) are the base for every user; only the AI tooling
      # list in overlays/ai-unstable.nix is swapped to unstable builds, and only
      # for the adults (nicky, aeiuno). sven/aaron stay on plain stable.
      unstablePkgs = import nixpkgs-unstable {
        inherit system;
        config.allowUnfree = true;
      };
      # Hermes Agent (Nous Research) built from upstream uv.lock via uv2nix.
      hermesAgent = unstablePkgs.callPackage ./packages/hermes-agent {
        uv2nix = uv2nix;
        pyproject-nix = pyproject-nix;
        pyproject-build-systems = pyproject-build-systems;
      };
      aiOverlay = import ./overlays/ai-unstable.nix {
        inherit unstablePkgs;
        inherit hermesAgent;
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
          # Secrets management (agenix CLI + age for encrypting/decrypting).
          agenix.packages.${system}.default
          age
        ];
      };

      # System 1 decision engines. Scope wrappers live beside them:
      # packages/laya/{home,nixos}.nix and packages/clm/home.nix. (One
      # packages.${system} assignment: flake outputs do not merge repeated
      # dynamic-attribute paths.)
      packages.${system} = {
        laya = pkgs.callPackage ./packages/laya { };
        clm = pkgs.callPackage ./packages/clm { };
        # Strata (packages/strata): CUDA inference engine for the A3000
        # (sm_86) + runtime wrappers; consumed via home-manager
        # (packages/strata/home.nix, `strata.enable`).
        strata = pkgs.callPackage ./packages/strata { strataSrc = forksStrata; };
      };

      nixosConfigurations =
        let
          # Per-host kernel choice. All hosts use the nixpkgs zen kernel
          # (BORE-ish interactive tuning, MQSS/BFQ): Hydra builds it without
          # LTO, so cache.nixos.org has the binary for the exact pinned nixpkgs
          # rev and `nix flake update` costs a download.
          #
          # The CachyOS LTO kernels (nix-cachyos-kernel flake) are gone: their
          # Attic cache only contains the versions that flake has already
          # compiled, so every `nix flake update` that advanced the pin could
          # mean a full local LTO kernel build (hours) before the cache caught
          # up. To go back, re-add the `nix-cachyos-kernel` input, its Attic
          # cache (nixConfig here + roles/nix.nix), and a module with
          #   nixpkgs.overlays = [ nix-cachyos-kernel.overlays.pinned ];
          #   boot.kernelPackages = pkgs.cachyosKernels.linuxPackages-cachyos-bore-lto-x86_64-v3;
          kernels = {
            linux-zen = { pkgs, ... }: {
              boot.kernelPackages = pkgs.linuxKernel.packages.linux_zen;
            };
          };
        in
        {
          laptop-hera = nixpkgs.lib.nixosSystem {
            system = "x86_64-linux";
            specialArgs = { inherit aiOverlay; };
            modules = [
              ./hosts/laptop-hera/laptop-hera-configuration.nix
              home-manager.nixosModules.home-manager
              agenix.nixosModules.default
              # Give nicky/aeiuno the AI-unstable pkgs overlay (opencode, pi,
              # jetbrains-toolbox, vscode, hermes-agent, magpie,
              # deepseek-harness); sven/aaron keep plain stable pkgs.
              ./users/ai-pkgs.nix
              # Inject the agenix home-manager module so home-manager users can
              # use `age.secrets` (nicky does for API keys).
              { home-manager.users.nicky.imports = [ agenix.homeManagerModules.default ]; }
              {
                home-manager.useGlobalPkgs = true;
                home-manager.useUserPackages = true;
                # Take over pre-existing unmanaged files (e.g. a plain ~/.zshrc
                # from zsh-newuser-install) instead of failing activation.
                home-manager.backupFileExtension = "backup";
                # Pass the Strata fork source (the flake input) to the users'
                # home modules; packages/strata/home.nix takes it as `strataSrc`.
                home-manager.extraSpecialArgs = { strataSrc = forksStrata; };
              }
              # TODO: enable a specific Dell XPS module once the exact model is
              # confirmed on the physical machine (e.g. `sudo dmidecode -s system-product-name`).
              # Likely candidates: dell-xps-13-9360 (same as laptop-xps), 9300, 9310.
              #           nixos-hardware.nixosModules.dell-xps-13-9360
              kernels.linux-zen
            ];
          };
          laptop-p16 = nixpkgs.lib.nixosSystem {
            system = "x86_64-linux";
            specialArgs = { inherit aiOverlay; };
            modules = [
              ./hosts/laptop-p16/laptop-p16-configuration.nix
              home-manager.nixosModules.home-manager
              agenix.nixosModules.default
              # Give nicky/aeiuno the AI-unstable pkgs overlay (opencode, pi,
              # jetbrains-toolbox, vscode, hermes-agent, magpie,
              # deepseek-harness); sven/aaron keep plain stable pkgs.
              ./users/ai-pkgs.nix
              { home-manager.users.nicky.imports = [ agenix.homeManagerModules.default ]; }
              {
                home-manager.useGlobalPkgs = true;
                home-manager.useUserPackages = true;
                # Take over pre-existing unmanaged files (e.g. a plain ~/.zshrc
                # from zsh-newuser-install) instead of failing activation.
                home-manager.backupFileExtension = "backup";
                # Pass the Strata fork source (the flake input) to the users'
                # home modules; packages/strata/home.nix takes it as `strataSrc`.
                home-manager.extraSpecialArgs = { strataSrc = forksStrata; };
              }
              nixos-hardware.nixosModules.lenovo-thinkpad # generic ThinkPad base; a model-specific module (e.g. thinkpad/p16s) may be added once confirmed via dmidecode
              kernels.linux-zen
            ];
          };
          laptop-xps = nixpkgs.lib.nixosSystem {
            system = "x86_64-linux";
            specialArgs = { inherit aiOverlay; };
            modules = [
              ./hosts/laptop-xps/laptop-xps-configuration.nix
              home-manager.nixosModules.home-manager
              agenix.nixosModules.default
              # Give nicky/aeiuno the AI-unstable pkgs overlay (opencode, pi,
              # jetbrains-toolbox, vscode, hermes-agent, magpie,
              # deepseek-harness); sven/aaron keep plain stable pkgs.
              ./users/ai-pkgs.nix
              { home-manager.users.nicky.imports = [ agenix.homeManagerModules.default ]; }
              {
                home-manager.useGlobalPkgs = true;
                home-manager.useUserPackages = true;
                # Take over pre-existing unmanaged files (e.g. a plain ~/.zshrc
                # from zsh-newuser-install) instead of failing activation.
                home-manager.backupFileExtension = "backup";
                # Pass the Strata fork source (the flake input) to the users'
                # home modules; packages/strata/home.nix takes it as `strataSrc`.
                home-manager.extraSpecialArgs = { strataSrc = forksStrata; };
              }

              nixos-hardware.nixosModules.dell-xps-13-9360

              kernels.linux-zen
            ];
          };
        };
    };
}
