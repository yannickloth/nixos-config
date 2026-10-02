{ config, lib, pkgs, ... }:

with lib;
{
  imports = [
    # Include the results of the hardware scan.
    ./hardware-configuration.nix

    # Shared family-laptop module set (IVP; see the file header for the deltas).
    ../../environments/family-laptop.nix

    # laptop-p16-only modules.
    ../../apps/benchmark.nix
    ../../apps/obs-studio.nix
    ../../apps/wine.nix

    # commonHm.hostName: home-manager modules cannot reach
    # config.networking.hostName, so the host name is passed explicitly. It
    # gates host-specific HM (Unsloth/Strata/CLM on laptop-p16).
    {
      home-manager.users.aeiuno = {
        imports = [ ../../users/aeiuno/aeiuno-hm.nix ];
        commonHm.hostName = "laptop-p16";
      };
    }
    {
      home-manager.users.nicky = {
        imports = [ ../../users/nicky/nicky-hm.nix ];
        commonHm.hostName = "laptop-p16";
      };
    }
    {
      home-manager.users.sven = {
        imports = [ ../../users/sven/sven-hm.nix ];
        commonHm.hostName = "laptop-p16";
      };
    }
    {
      home-manager.users.aaron = {
        imports = [ ../../users/aaron/aaron-hm.nix ];
        commonHm.hostName = "laptop-p16";
      };
    }
  ];
  # In this file comes everything that is specific to this host.
  networking.hostName = "laptop-p16"; # Define your hostname.

  # Syncthing device name for this host (see services/syncthing/pool.nix).
  services.syncthing.self = "laptop-p16";

  # 128 GiB RAM -> run browser profiles in RAM.
  roles.psd.enable = true;

  # 128 GiB RAM -> /tmp in RAM. Volatile by nature, so no cleanOnBoot wipe
  # (deleting psd's tens of thousands of small profile files was slow at boot).
  boot.tmp.useTmpfs = true;
  boot.tmp.tmpfsSize = "50%";
  boot.tmp.cleanOnBoot = false;

  # Bootloader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # 128 GiB RAM -> parallel builds with all cores.
  roles.nix.maxJobs = 12;
  roles.nix.cores = 0;

  # Strata's expert arena uses MAP_HUGETLB|MAP_HUGE_2MB; that needs both the
  # global hugepage pool (boot.kernel.sysctl) and an unlimited locked-memory
  # limit for the process doing the mmap.
  # - PAM login limits cover interactive shells after login/reboot.
  # - systemd's system-wide default also raises the limit for the user manager
  #   and all user units (including the strata service and any systemd-run
  #   scopes), which PAM alone does not reach on a graphical session.
  security.pam.loginLimits = [{
    domain = "nicky";
    item = "memlock";
    type = "-";
    value = "unlimited";
  }];
  security.pam.services.sddm.limits = [{
    domain = "nicky";
    item = "memlock";
    type = "-";
    value = "unlimited";
  }];
  # systemd's defaults raise the limit for the system manager (and thus the
  # user@.service) and for the user manager, which PAM alone does not reach on
  # a graphical session. nixos-26.05 has systemd.settings.Manager for the
  # system instance and systemd.user.extraConfig for the user instance.
  systemd.settings.Manager.DefaultLimitMEMLOCK = "infinity";
  systemd.user.extraConfig = "DefaultLimitMEMLOCK=infinity";
}
