# role to be used on all systems

{ config, lib, pkgs, ... }:

with lib;

{
  imports = [
    ./nix.nix
    ./home-readme.nix
    ../security/kids.nix
    ../services/snapshots.nix
    ../services/home-quota.nix
    ../services/usb-scan.nix
    ../services/secrets.nix
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

    # Persistent system journal so parents can review kids' sessions across
    # reboots (journalctl --since ... / journalctl -u ... / -b -1).
    services.journald = {
      storage = mkDefault "persistent";
      extraConfig = ''
        SystemMaxUse=2G
        SystemKeepFree=1G
      '';
    };

    # Kernel hardening applied via sysctls on the (CachyOS) kernel — no kernel
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

    # Python interpreter available to every user (kids' programming, Open WebUI
    # filter payloads). The repo's own scripts are Java 25 compact source files
    # (users/NaturalScroll.java, services/MalcontentMerge.java,
    # services/ai-chat/SeedGates.java).
    environment.systemPackages = [ pkgs.python3 ];

    # Flatpak apps installed per-user that malcontent's allowlist gates for the
    # kids (malcontent only filters flatpak apps; it filters per-user apps by
    # app id just like system ones). Kept in sync with the allowlist in
    # services/malcontent.nix. Browsers stay in Nix: Firefox needs its
    # declarative kid policies (users/kid-firefox-policies.nix). The kids'
    # office/creative/media/mail apps (libreoffice, gimp, krita, VLC, Geary)
    # come from flatpak so malcontent can gate them without a Nix rebuild.
    # Overrides grant access to the shared family drop folder (/filedrop).
    # adultApps is the same list minus the apps nicky/aeiuno already have from
    # Nixpkgs (gimp, krita, libreoffice, vlc, obsidian, dolphin, gwenview,
    # kalk, okular), so the adults never end up with two copies of an app.
    apps.flatpak = {
      enable = mkDefault true;
      apps = [
        "app/org.gnome.Books/x86_64/stable"
        "app/org.gnome.Calculator/x86_64/stable"
        "app/org.gnome.Cheese/x86_64/stable"
        "app/org.gnome.Clocks/x86_64/stable"
        "app/org.gnome.Epiphany/x86_64/stable"
        "app/org.gnome.Geary/x86_64/stable"
        "app/org.gnome.Logs/x86_64/stable"
        "app/org.gnome.Maps/x86_64/stable"
        "app/org.gnome.Music/x86_64/stable"
        "app/org.gnome.Notes/x86_64/stable"
        "app/org.gnome.SystemMonitor/x86_64/stable"
        "app/org.gnome.Totem/x86_64/stable"
        "app/org.kde.dolphin/x86_64/stable"
        "app/org.kde.gwenview/x86_64/stable"
        "app/org.kde.kalk/x86_64/stable"
        "app/org.kde.okular/x86_64/stable"
        "app/org.kde.krita/x86_64/stable"
        "app/org.gimp.GIMP/x86_64/stable"
        "app/org.libreoffice.LibreOffice/x86_64/stable"
        "app/org.videolan.VLC/x86_64/stable"
        "app/md.obsidian.Obsidian/x86_64/stable"
        "app/org.stellarium.Stellarium/x86_64/stable"
      ];
      adultApps = [
        "app/org.gnome.Books/x86_64/stable"
        "app/org.gnome.Calculator/x86_64/stable"
        "app/org.gnome.Cheese/x86_64/stable"
        "app/org.gnome.Clocks/x86_64/stable"
        "app/org.gnome.Epiphany/x86_64/stable"
        "app/org.gnome.Geary/x86_64/stable"
        "app/org.gnome.Logs/x86_64/stable"
        "app/org.gnome.Maps/x86_64/stable"
        "app/org.gnome.Music/x86_64/stable"
        "app/org.gnome.Notes/x86_64/stable"
        "app/org.gnome.SystemMonitor/x86_64/stable"
        "app/org.gnome.Totem/x86_64/stable"
        "app/org.stellarium.Stellarium/x86_64/stable"
      ];
      overrides = {
        "org.kde.krita" = [ "--filesystem=/filedrop" ];
        "org.gimp.GIMP" = [ "--filesystem=/filedrop" ];
        "org.libreoffice.LibreOffice" = [ "--filesystem=/filedrop" ];
        "org.videolan.VLC" = [ "--filesystem=/filedrop" ];
        "md.obsidian.Obsidian" = [ "--filesystem=/filedrop" ];
      };
    };

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
