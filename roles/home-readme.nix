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
      path = [ pkgs.e2fsprogs pkgs.coreutils ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      # chattr -i first so updates flow on rebuild/boot, then re-immortalize.
      script = concatStringsSep "\n" (mapAttrsToList
        (user: file: ''
          target="/home/${user}/README.md"
          ${pkgs.e2fsprogs}/bin/chattr -i "$target" 2>/dev/null || true
          ${pkgs.coreutils}/bin/install -o root -g root -m 0444 ${file} "$target"
          ${pkgs.e2fsprogs}/bin/chattr +i "$target"
        '')
        config.roles.homeReadme.files);
    };
  };
}
