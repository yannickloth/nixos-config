# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

### System Management
- **Update packages**: `nix flake update` (updates flake.lock)
- **Apply configuration**: `sudo nixos-rebuild switch --flake ./`
- **Format Nix files**: `nixpkgs-fmt` or `nixfmt-rfc-style`
- **Check syntax**: Use `nixd` language server for Nix files

### Build and Test
- **Test configuration**: `sudo nixos-rebuild test --flake ./` (applies without making it default)
- **Build configuration**: `sudo nixos-rebuild build --flake ./` (builds without switching)

## Architecture

This is a modular NixOS configuration using Nix flakes with the following structure:

### Core Architecture
- **Flake-based**: Uses `flake.nix` as entry point with nixpkgs-unstable and home-manager
- **Multi-host support**: Configurations for multiple laptops (laptop-hera, laptop-p16, laptop-xps)
- **Modular design**: Separates concerns into roles, profiles, users, and hardware-specific modules

### Directory Structure
- `hosts/`: Host-specific configurations and hardware configurations
- `profiles/`: Feature-specific modules (bluetooth, games, gnome, plasma, etc.)
- `users/`: User account definitions and home-manager configurations
- `roles/`: Common base configuration applied to all systems
- `hardware/`: Hardware-specific modules (Intel CPU/graphics, printers, etc.)
- `modules/`: Custom modules (systemPackages, timers, etc.)
- `packages/`: Custom package definitions
- `environments/`: Environment-specific configurations

### Key Configuration Patterns
- **Profile-based features**: Each profile in `profiles/` enables specific functionality
- **Conditional groups**: User groups are conditionally added based on enabled services
- **Hardware abstraction**: Hardware-specific config separated from host logic
- **Home Manager integration**: User configurations managed via home-manager modules

### Host Configuration Flow
1. `flake.nix` defines nixosConfigurations for each host
2. Host configuration imports base modules, user configs, and hardware configs
3. Profiles are selectively imported to enable features
4. Hardware modules provide device-specific settings

### Secrets Management
- No specific secret management tool is used
- Secrets are either hashed in .nix files or excluded from repo
- CIFS credentials stored in `smb-secrets` file (not tracked in git)

### External Dependencies
- **nixos-hardware**: Hardware-specific configurations from NixOS/nixos-hardware
- **home-manager**: User environment and dotfile management
- **Binary caches**: Uses cache.nixos.org with experimental features enabled

## Development Notes
- All systems use `nixpkgs.config.allowUnfree = true`
- Nix flakes and nix-command experimental features are enabled
- Store optimization and garbage collection are configured
- Systems use mutable users disabled by default for security