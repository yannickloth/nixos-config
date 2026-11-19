{ config, lib, pkgs, ... }:

with lib;
{
  imports = [
    # Include the results of the hardware scan.
    # NOTE: Generate this on the machine with:
    # sudo nixos-generate-config --show-hardware-config > ./hardware-configuration.nix
    ./hardware-configuration.nix

    # Minimal server environment: base policy, SSH, Tailscale, Syncthing, podman.
    # No gaming, no kids' services, no peripheral daemons.
    ../../environments/server.nix

    # Desktop stack (KDE Plasma, same as the family hosts): server-nike is
    # also used as a powerful desktop, not only as the inference server.
    ../../desktop/console.nix
    ../../desktop/pipewire.nix
    ../../desktop/xserver.nix
    ../../desktop/xwayland.nix
    ../../desktop/plasma.nix

    # Pinned age host identity (services/host-age.nix): the keypair in
    # ssh-keys/hosts/server-nike is pinned as the /etc/ssh host key (private key installed per
    # secrets-structure/README.md) and audited against secrets.nix at build time, so a stale recipient set
    # fails the build instead of locking the host out of its own logins.
    ../../services/host-age.nix
    {
      services.hostAge = {
        enable = true;
        pubKey = ../../ssh-keys/hosts/server-nike.pub;
      };
    }

    # commonHm.hostName: home-manager modules cannot reach
    # config.networking.hostName, so the host name is passed explicitly. It
    # gates host-specific HM (Unsloth/Strata/Orca on the inference hosts).
    #
    # Same user set and software config as laptop-p16: server-nike's intended
    # use is inference (daily), with desktop use in between, so nicky's
    # inference stack (Strata, Unsloth Studio with GPU passthrough, the
    # always-on Orca server) runs here too — see the isP16 || isNike gates in
    # users/nicky/nicky-hm.nix.
    {
      home-manager.users.aeiuno = {
        imports = [ ../../users/aeiuno/aeiuno-hm.nix ];
        commonHm.hostName = "server-nike";
      };
    }
    {
      home-manager.users.nicky = {
        imports = [ ../../users/nicky/nicky-hm.nix ];
        commonHm.hostName = "server-nike";
      };
    }
    {
      home-manager.users.sven = {
        imports = [ ../../users/sven/sven-hm.nix ];
        commonHm.hostName = "server-nike";
      };
    }
    {
      home-manager.users.aaron = {
        imports = [ ../../users/aaron/aaron-hm.nix ];
        commonHm.hostName = "server-nike";
      };
    }
  ];
  # In this file comes everything that is specific to this host.
  # GPU passthrough for the Unsloth Studio container
  # (packages/unsloth-studio/container.nix, --device nvidia.com/gpu=all): the
  # module writes the CDI spec at boot (/var/run/cdi) and registers it in
  # containers.conf.
  hardware.nvidia-container-toolkit = {
    enable = true;
    suppressNvidiaDriverAssertion = true; # driver provided by hardware.nvidia module
  };

  # Disable the boot-time CDI generator. It waits for /dev/nvidia0 which
  # may not appear until after the initrd finishes (the kernel module
  # loading is what creates the device node, but the udev settle in
  # nixpkgs doesn't wait for NVIDIA driver binding). Disabling the
  # multi-user trigger eliminates the boot failure; the nixpkgs udev rule
  # (KERNEL=="nvidia", RUN+=restart) will still trigger it exactly once
  # when the driver actually loads.
  systemd.services.nvidia-container-toolkit-cdi-generator.enable = false;

  networking.hostName = "server-nike"; # Define your hostname.

  # Syncthing device name for this host (see services/syncthing/pool.nix).
  services.syncthing.self = "server-nike";

  # The second SATA SSD (/data, LUKS+btrfs) carries the Syncthing data tree.
  # Bind-mount it at the canonical /sync path used by services/syncthing/default.nix,
  # so only the backing store differs between hosts. This replaces the previous
  # /sync -> /data/sync symlink, which raced the module's `mkdir -p /sync`
  # activation script (alphabetical script order created a real /sync first, and
  # the silent rmdir/ln conversion then degraded into a nested /sync/sync
  # symlink). With a bind mount there is no conversion left to race: /sync is a
  # plain mount point, systemd orders it after /data by itself, and tmpfiles/ACL
  # rules apply unchanged.
  fileSystems."/sync" = {
    device = "/data/sync";
    fsType = "none";
    options = [ "bind" ];
    depends = [ "/data" ];
  };

  # systemd mount units do not create their bind source, and activation runs
  # before mounts at boot, so the bind source is created by a unit ordered
  # between /data and /sync (the activation script below only handles the
  # legacy /sync symlink migration at switch time).
  systemd.services.syncthing-nike-data-dir = {
    description = "Create the /data/sync bind source before /sync mounts";
    wantedBy = [ "sync.mount" ];
    requires = [ "data.mount" ];
    after = [ "data.mount" ];
    before = [ "sync.mount" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      mkdir -p /data/sync /data/containers/nicky /data/unsloth
      chown syncthing:syncthing /data/sync
      chmod 2770 /data/sync
      chown nicky:nicky /data/containers/nicky /data/unsloth
      chmod 2770 /data/containers/nicky /data/unsloth
    '';
  };

  # One-time migration: if the legacy /sync symlink is still there, swap it for
  # the mount point dir (the bind mount itself is handled by the unit above).
  system.activationScripts.syncthing-nike-data = {
    deps = [ "users" "groups" ];
    text = ''
      if [ -L /sync ]; then
        rm /sync
        mkdir -p /sync
      fi
    '';
  };

  # Dell Precision Tower 5810: desktop, not a laptop — no lid, no battery.
  # Disable suspend/hibernate: an inference server must stay up.
  systemd.sleep.settings.Sleep = {
    AllowSuspend = false;
    AllowHibernation = false;
    AllowSuspendThenHibernate = false;
    AllowHybridSleep = false;
  };

  # Strata's 39.97 GiB expert arena uses MAP_HUGETLB|MAP_HUGE_2MB and needs the
  # whole mmap covered (all-or-nothing, else it falls back to 4 KiB pages).
  # 22528 * 2 MiB = 44 GiB: the arena plus ~4 GiB headroom. Only reserve it when
  # nicky's home-manager profile actually enables Strata on this host; a fixed
  # pool is parked RAM that normal allocations cannot use. 44 GiB covers ONE
  # engine: a second concurrent engine needs its own ~40 GiB arena.
  boot.kernel.sysctl."vm.nr_hugepages" =
    lib.mkIf (config.home-manager.users.nicky.strata.enable or false) 22528;

  # Bootloader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # Kernel + matching NVIDIA driver: Use `linux_6_18` (the current latest
  # supported mainline kernel) and its paired NVIDIA driver (`nvidia_x11`).
  #
  # Why: The user is on `linux_zen` 7.3.4. The proprietary NVIDIA driver (even
  # the bleeding-edge 615.x `new_feature` branch) lags behind brand-new kernels
  # like 7.x, causing "API mismatch" and "Driver/Library version mismatch" errors.
  # `linux_6_18` is the current latest stable mainline kernel in nixpkgs, and its
  # `nvidia_x11` package includes community patches to support the latest kernels.
  #
  # Note: We use `linux_6_18` instead of `linux_zen` because NVIDIA does not
  # support the heavy Zen patches (Bore, RT, etc.). Vanilla kernel 6.18 is
  # compatible with the patched driver; kernel 7.x Zen is not.
  boot.kernelPackages = pkgs.linuxKernel.packages.linux_6_18;

  # Belgian home server (roles/base.nix defaults to Europe/Luxembourg).
  time.timeZone = "Europe/Brussels";

  # Dell 5810: Xeon E5-1650 v3 (8C/16T) — parallel builds with all cores.
  roles.nix.maxJobs = 16;
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
  security.pam.services.gdm.limits = [{
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

  # nicky's always-on Orca runtime server (packages/orca/home.nix,
  # orca.server.enable) must survive logout, which needs lingering.
  users.users.nicky.linger = true;

  # The Orca runtime server listens on TCP 6768 and is meant to be reached only
  # by Tailscale peers (other laptops pair to it over the mesh), same CGNAT gate
  # as nix-serve in environments/laptop-firewall.nix. Kept in the host rather
  # than the HM module because orca.server is a home-manager option and cannot
  # touch networking.firewall.
  networking.firewall.extraInputRules = ''
    tcp dport 5000 ip saddr 100.64.0.0/10 accept  # nix-serve (Tailscale)
    tcp dport 5000 ip saddr 192.168.178.0/24 accept # nix-serve (local LAN)
    tcp dport 6768 ip saddr 100.64.0.0/10 accept  # orca runtime server (Tailscale)
  '';

  # Dell 5810: no discrete Intel iGPU on the Xeon, so no prime offload needed.
  # The RTX 3060 (Ampere GA106, sm_86) is the only GPU. No power management on a
  # server — keep it at full boost for inference workloads.
  hardware.nvidia = {
    # NVIDIA RTX 3060 12GB (Ampere GA106, compute capability 8.6)
    dynamicBoost.enable = false; # desktop card, no dynamic boost
    gsp.enable = true; # NVIDIA GPU System Processor — offloads low-level GPU mgmt
    modesetting.enable = true; # Required for the NVIDIA driver
    nvidiaSettings = true;
    # Paired with `linux_latest` (see above): the nvidia_x11 package includes
    # community patches to support the absolute newest kernel versions.
    package = config.boot.kernelPackages.nvidia_x11;
    powerManagement = {
      enable = false; # Never sleep the GPU — inference server
      finegrained = false;
    };
    videoAcceleration = true;
  };

  # NVIDIA kernel modules are out-of-tree (built by the driver package), so they
  # need to be added to extraModulePackages for linux-modules-shrunk to find
  # them when resolving initrd dependencies.
  boot.extraModulePackages = [
    config.boot.kernelPackages.nvidia_x11.mod
  ];

  # Server stance: no power saving on any bus component.
  boot.kernel.sysctl."vm.swappiness" = 10;
  boot.kernel.sysctl."fs.inotify.max_user_watches" = 2097152;

  # Disable suspend at kernel level too (ACPI).
  boot.blacklistedKernelModules = lib.optionals (!config.hardware.enableRedistributableFirmware) [
    "ath3k"
  ];

  # Intel Xeon microcode (haswell-ep family).
  hardware.cpu.intel.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;

  # nvidia-smi is in the nvidia-x11 package's `bin` output (the driver runfile
  # ships it alongside nvidia-cuda-mps-control, etc.); not a standalone nixpkgs
  # derivation, so it must be pulled from the multi-output package explicitly.
  environment.systemPackages = [ config.hardware.nvidia.package.bin ];
}
