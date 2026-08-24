# role to be used on all systems

{ config, lib, pkgs, ... }:

with lib;

{
  imports = [
    ./nix.nix
    ./home-readme.nix
  ];

  config = {
    # use UTC by default, do not leak location
    time.timeZone = mkDefault "Europe/Luxembourg";

    # You are not allowed to manage users manually by default
    users.mutableUsers = mkDefault false;

    # clean tmp on boot and remove all residuals there
    boot.tmp.cleanOnBoot = mkDefault true;

    # enable NTFS support (bcachefs removed: no bcachefs filesystems in use,
    # and it pulled the heavy bcachefs-tools Rust build into every system)
    boot.supportedFilesystems = [ "ntfs" ];

    # i think apple will sue me before oss does
    nixpkgs.config.allowUnfree = true;

    # If set to true, Nix automatically detects files in the store that have identical contents, and replaces them with hard links to a single copy. This saves disk space.
    nix.settings.auto-optimise-store = true;

    # vim as default editor
    #programs.vim.defaultEditor = true;

    boot.enableContainers = mkDefault true;

    system.nixos = {
      versionSuffix = mkDefault ".latest";
      revision = mkDefault "latest";
    };

    # enable systemd-oomd on all systems (replaces earlyoom: first-class,
    # kills the heaviest process on memory pressure instead of locking up)
    systemd.oomd = {
      enable = mkDefault true;
      enableRootSlice = mkDefault true;
      enableUserSlices = mkDefault true;
    };

    # enable fstrim on all systems, running fstrim weekly is a good practice
    services.fstrim.enable = mkDefault true;

    # replace ntpd by chrony on all systems
    services.chrony = {
      enable = mkDefault true;
    };

    # Python interpreter available to every user (scripting, kids' programming).
    environment.systemPackages = [ pkgs.python3 ];

    # Root-owned, immutable README.md in each family member's home, on every host
    # (see roles/home-readme.nix). Parents share one file; sven and aaron get
    # their own, age-appropriate versions.
    roles.homeReadme = {
      enable = mkDefault true;
      files = {
        nicky = ../users/readmes/parents.md;
        aeiuno = ../users/readmes/parents.md;
        sven = ../users/readmes/sven.md;
        aaron = ../users/readmes/aaron.md;
      };
    };
  };
}
