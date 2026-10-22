{ config, lib, pkgs, ... }:

with lib;

{
  # Install a root-owned, read-only, immutable README.md into each user's home
  # directory (so even the owner of the home dir cannot edit or delete it).
  # Content is versioned per user under users/readmes/<user>.md.
  options.roles.homeReadme = {
    enable = mkOption {
      type = types.bool;
      default = false;
      description = "Install immutable per-user README.md files in /home/<user>.";
    };
    files = mkOption {
      type = types.attrsOf types.path;
      default = { };
      example = { nicky = ../users/readmes/parents.md; };
      description = "Mapping of username -> markdown source installed as /home/<user>/README.md.";
    };
  };

  config = mkIf config.roles.homeReadme.enable {
    systemd.services.home-readmes = {
      description = "Install immutable per-user README files";
      wantedBy = [ "multi-user.target" ];
      # Run before any user session can replace the file, and only after /home
      # exists (it may be a separate mount or a network filesystem).
      before = [ "systemd-user-sessions.service" ];
      requiresMountsFor = [ "/home" ];
      path = [ pkgs.e2fsprogs pkgs.coreutils ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      # chattr -i first so updates flow on rebuild/boot, then re-immortalize.
      # The target lives in a directory the user controls, so only ever write
      # through a regular destination (never a symlink or a directory).
      script = ''
        set -euo pipefail
        warn() { echo "home-readmes: $*" >&2; }

        install_readme() {
          local target="$1" src="$2"
          if [ -L "$target" ] || { [ -e "$target" ] && [ ! -f "$target" ]; }; then
            warn "refusing to replace non-regular $target"
            return 0
          fi
          ${pkgs.e2fsprogs}/bin/chattr -i "$target" 2>/dev/null || true
          ${pkgs.coreutils}/bin/install --no-target-directory -o root -g root -m 0444 "$src" "$target"
          if ! ${pkgs.e2fsprogs}/bin/chattr +i "$target" 2>/dev/null; then
            warn "chattr +i failed on $target (filesystem without immutable support); the README is not immutable"
          fi
        }

        ${concatStringsSep "\n" (mapAttrsToList
          (user: file: ''
            install_readme "${config.users.users.${user}.home or "/home/${user}"}/README.md" ${file}
          '')
          config.roles.homeReadme.files)}
      '';
    };
  };
}
