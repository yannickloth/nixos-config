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
    # Strata (github.com/Niko1221/Strata) is not a flake input: packages/strata
    # fetches it directly with fetchFromGitHub, pinned to v0.1.40.3 in
    # engine.nix/default.nix. (It used to be the private yannickloth/forks-Strata
    # fork's sm_86 branch; upstream 0.1.40.3 now carries every engine change the
    # fork had, so the fork only added a bench harness - see git history.)
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

  outputs = { nixpkgs, nixpkgs-unstable, home-manager, nixos-hardware, agenix, uv2nix, pyproject-nix, pyproject-build-systems, ... }:
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
          nixpkgs-fmt # legacy formatter; nixfmt (RFC style) is the target (see plan)
          nixfmt # RFC-style formatter: `nix fmt`
          deadnix # dead-code detection for Nix
          statix # Nix lint/anti-pattern checks
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

      # `nix fmt` target (RFC-style). Bulk reformat is deferred until the
      # Phase 0/2 cleanups land, so CI does not enforce formatting yet.
      formatter.${system} = pkgs.nixfmt;

      # System 1 decision engines. Scope wrappers live beside them:
      # packages/laya/{home,nixos}.nix and packages/clm/home.nix. (One
      # packages.${system} assignment: flake outputs do not merge repeated
      # dynamic-attribute paths.)
      packages.${system} = {
        laya = pkgs.callPackage ./packages/laya { };
        clm = pkgs.callPackage ./packages/clm { };
        # Strata (packages/strata): CUDA inference engine for the A3000
        # (sm_86) + runtime wrappers; consumed via home-manager
        # (packages/strata/home.nix, `strata.enable`). Built WITHOUT the
        # strata-vision image encoder: image support drops throughput from
        # ~35 to ~22 tok/s, so vision stays off.
        strata = pkgs.callPackage ./packages/strata { vision = false; };
        # Orca (packages/orca): the released Electron AppImage wrapped as a
        # normal derivation (appimageTools.wrapType2). Consumed via home-manager
        # (packages/orca/home.nix) and also exposed here for `nix build .#orca`
        # / `nix-update`.
        orca = pkgs.callPackage ./packages/orca { };
        # PhotoCraft (packages/photocraft): clean-room Photoshop
        # reimplementation, packaged from the upstream AppImage. Installed for
        # every user via users/common-hm.nix; exposed here for `nix build
        # .#photocraft` / `nix-update`.
        photocraft = pkgs.callPackage ./packages/photocraft { };
      };

      nixosConfigurations =
        let
          # Default kernel: nixpkgs zen (BORE-ish interactive tuning); Hydra
          # builds it, so `nix flake update` is a download. The CachyOS LTO
          # kernels were dropped: their cache lagged each pin and could trigger
          # a multi-hour local LTO build. See git history to reintroduce.
          #
          # NVIDIA caveat: linux_zen is on 7.2, whose DRM atomic-state rename
          # (`drm_atomic_state` -> `drm_atomic_commit`) and strncpy removal are
          # only handled by NVIDIA >= 595.99.02 (nixpkgs-unstable). Stable's
          # 595.71.05 does not compile against 7.2, so the NVIDIA hosts (hera,
          # p16) pin the desktop-tuned XanMod 6.18 LTS instead (see mkHost).
          #
          # Home-manager + shared-module wiring common to every host.
          commonModules = [
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
            }
          ];

          # One host: its configuration module + any host-only modules, on top
          # of commonModules. `kernelPackages` defaults to the nixpkgs zen
          # kernel; the NVIDIA hosts override it to XanMod 6.18 LTS because the
          # stable NVIDIA driver cannot build against zen's 7.2 (see above).
          mkHost =
            {
              configModule,
              extraModules ? [ ],
              kernelPackages ? pkgs.linuxKernel.packages.linux_zen,
            }:
            nixpkgs.lib.nixosSystem {
              system = "x86_64-linux";
              specialArgs = { inherit aiOverlay; };
              modules = [ configModule ] ++ extraModules ++ commonModules ++ [
                { boot.kernelPackages = kernelPackages; }
              ];
            };
        in
        {
          # GTX 1050 Ti (proprietary modules).
          laptop-hera = mkHost {
            configModule = ./hosts/laptop-hera/laptop-hera-configuration.nix;
            kernelPackages = pkgs.linuxKernel.packages.linux_xanmod;
          };

          # generic ThinkPad base; a model-specific module (e.g. thinkpad/p16s)
          # may be added once confirmed via dmidecode.
          # RTX A3000 (open modules).
          laptop-p16 = mkHost {
            configModule = ./hosts/laptop-p16/laptop-p16-configuration.nix;
            extraModules = [ nixos-hardware.nixosModules.lenovo-thinkpad ];
            kernelPackages = pkgs.linuxKernel.packages.linux_xanmod;
          };

          laptop-xps = mkHost {
            configModule = ./hosts/laptop-xps/laptop-xps-configuration.nix;
            extraModules = [ nixos-hardware.nixosModules.dell-xps-13-9360 ];
          };
        };
    };
}
