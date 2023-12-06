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
    boot.supportedFilesystems = [ "ntfs" ];

    # i think apple will sue me before oss does
    nixpkgs.config.allowUnfree = true;

    # vim as default editor
    #programs.vim.defaultEditor = true;

    boot.enableContainers = mkDefault true;

    documentation.doc.enable = mkDefault true;

    system.nixos = {
      versionSuffix = mkDefault ".latest";
      revision = mkDefault "latest";
    };

    # enable earlyoom on all systems
    services.earlyoom.enable = mkDefault true;

    # enable fstrim on all systems, running fstrim weekly is a good practice
    services.fstrim.enable = mkDefault true;

    # replace ntpd by chrony
    services.chrony = {
      enable = mkDefault true;
    };
  };
}
