# role to be used on all systems

{ config, lib, ... }:

with lib;

{
  imports = [
    ../profiles/nix.nix
  ];

  config = {
    # use UTC by default, do not leak location
    time.timeZone = mkDefault "Europe/Luxembourg";

    # You are not allowed to manage users manually by default
    users.mutableUsers = mkDefault false;

    # clean tmp on boot and remove all residuals there
    boot.tmp.cleanOnBoot = mkDefault true;

    # enable NTFS support
    boot.supportedFilesystems = [ "bcachefs" "ntfs" ];

    # i think apple will sue me before oss does
    nixpkgs.config.allowUnfree = true;

    # If set to true, Nix automatically detects files in the store that have identical contents, and replaces them with hard links to a single copy. This saves disk space.
    nix.settings.auto-optimise-store=true;

    # vim as default editor
    #programs.vim.defaultEditor = true;

    boot.enableContainers = mkDefault true;

    system.nixos = {
      versionSuffix = mkDefault ".latest";
      revision = mkDefault "latest";
    };

    # enable earlyoom on all systems
    services.earlyoom.enable = mkDefault true;

    # enable fstrim on all systems, running fstrim weekly is a good practice
    services.fstrim.enable = mkDefault true;

    # replace ntpd by chrony on all systems
    services.chrony = {
      enable = mkDefault true;
    };
  };
}
