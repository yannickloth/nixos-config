# role to be used on all systems

{ config, lib, pkgs, ... }:

with lib;

{
  imports = [
    ./btrfs.nix
    ./nix.nix
    ./home-readme.nix
    ./fhs-compat.nix
    ../security/kids.nix
    ../services/snapshots.nix
    ../services/usb-mount.nix
    ../services/usb-scan.nix
    ../services/secrets.nix
  ];

  config = {
    # Default timezone (Europe/Luxembourg; environments/laptop.nix pins the
    # same value for laptops). Not UTC — this is a home LAN, not a server.
    time.timeZone = mkDefault "Europe/Luxembourg";

    # You are not allowed to manage users manually by default
    users.mutableUsers = mkDefault false;

    # clean tmp on boot and remove all residuals there
    boot.tmp.cleanOnBoot = mkDefault true;

    # NTFS support for the filesystem layer lives in services/usb-mount.nix
    # (imported above), together with the udisks2 user-mount stack. bcachefs
    # removed: no bcachefs filesystems in use, and it pulled the heavy
    # bcachefs-tools Rust build into every system.
    # The NTFS userspace tools (ntfsinfo, mkfs.ntfs, ntfsfix) come from
    # ntfs3g, which boot.supportedFilesystems = [ "ntfs" ] installs.

    # i think apple will sue me before oss does
    nixpkgs.config.allowUnfree = true;

    # If set to true, Nix automatically detects files in the store that have identical contents, and replaces them with hard links to a single copy. This saves disk space.
    nix.settings.auto-optimise-store = true;

    # vim as default editor
    #programs.vim.defaultEditor = true;

    boot.enableContainers = mkDefault true;

    system.nixos = {
      versionSuffix = mkDefault ".latest";
      revision = mkDefault "latest-2";
    };

    # General-purpose sysadmin tools, plus the interpreters every user gets.
    environment.systemPackages = with pkgs; [
      btop # top/htop replacement, CPU/memory/network/disk view
      # Python interpreter available to every user (kids' programming). The repo's
      # own scripts are Java 25 compact source files (users/NaturalScroll.java,
      # services/MalcontentMerge.java).
      python3
    ];
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

    # Persistent system journal so parents can review kids' sessions across
    # reboots (journalctl --since ... / journalctl -u ... / -b -1).
    services.journald = {
      storage = mkDefault "persistent";
      extraConfig = ''
        SystemMaxUse=2G
        SystemKeepFree=1G
      '';
    };

    # Kernel hardening applied via sysctls on the (linux-zen) kernel — no kernel
    # swap. Note: dmesg/perf need root (parents have sudo); kexec is disabled.
    boot.kernel.sysctl = {
      "kernel.dmesg_restrict" = 1;
      "kernel.kptr_restrict" = 2;
      "kernel.perf_event_paranoid" = 3;
      "kernel.unprivileged_bpf_disabled" = 1;
      "net.core.bpf_jit_harden" = 2;
      "kernel.panic_on_oops" = 1;
      "kernel.kexec_load_disabled" = 1;
    };

    # python3 is installed in the systemPackages block above. One module may
    # define an option once, so package additions belong in that single block.

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
