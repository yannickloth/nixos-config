{ config, lib, pkgs, ... }:

with lib;
{
  imports = [
    # Include the results of the hardware scan.
    # NOTE: Generate this on the machine with:
    # sudo nixos-generate-config --show-hardware-config > ./hardware-configuration.nix
    ./hardware-configuration.nix

    # Proprietary NVIDIA driver, kernel and driver from one evaluation
    # (see the file header for why).
    ../../hardware/nvidia_ampere.nix

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

    # NetworkManager (host delta, like the desktop stack above): the base
    # server environment leaves DHCP to dhcpcd, but the Plasma panel's network
    # applet (plasma-nm) only shows up when NetworkManager is running. Same
    # setup as the family laptops/desktops via environments/family-laptop.nix.
    # NixOS disables dhcpcd automatically once networkmanager is enabled.
    ../../services/network-manager.nix

    # Printer stack (same as laptop-p16): avahi for mDNS, CUPS, hardware
    # profiles, and the offline-aware ensure-printers wrapper.
    # Override the server-base disables from environments/server.nix.
    ../../hardware/printers/brother-mfcl2700dw.nix
    ../../hardware/printers/epson-xp15000.nix
    ../../services/avahi.nix
    ../../services/printing.nix
    ../../services/scanning.nix
    {
      services.avahi.enable = lib.mkForce true;
      services.printing.enable = lib.mkForce true;
    }

    # PostgreSQL backs the LiteLLM proxy's admin UI, virtual keys and spend
    # ledger. The module creates the `litellm` role/database only when the
    # proxy is enabled (services/postgresql.nix).
    ../../services/postgresql.nix

    # LiteLLM rank gateway (services/litellm-proxy.nix): the single LLM
    # endpoint for opencode/pi on every host. Sits next to Unsloth Studio
    # (loopback) and reaches Strata on laptop-p16 over Tailscale.
    ../../services/litellm-proxy.nix

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
  # Writes the CDI spec to /var/run/cdi and registers /var/run/cdi in
  # containers.conf, so `--device nvidia.com/gpu=all` resolves.
  #
  # The module asserts that "nvidia" is in services.xserver.videoDrivers (see
  # below), so it needs no suppressNvidiaDriverAssertion override: a broken
  # driver configuration now fails at build time instead of at container start.
  hardware.nvidia-container-toolkit.enable = true;

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

  # No Strata on server-nike: it is the daily workstation. Strata inference
  # is delegated to laptop-p16 (RTX A3000 12GB). No hugepage pool needed.

  # Bootloader — keep 5 generations max to prevent EFI partition fill-up.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.loader.systemd-boot.configurationLimit = 5;

  # Belgian home server (roles/base.nix defaults to Europe/Luxembourg).
  time.timeZone = "Europe/Brussels";

  # Dell 5810: Xeon E5-1650 v3 (6C/12T, Haswell-EP, 3.5 GHz) — parallel
  # builds with all cores.
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
  # touch networking.firewall. Same for strata (:8080), unsloth-studio (:8888)
  # and the LiteLLM proxy (:4000) below: reachable from the other inference
  # host, the LAN and the tailnet (the private-range set from lib, IPv6
  # included). Loopback needs no rule: the firewall accepts lo by default.
  networking.firewall.extraInputRules = ''
    tcp dport 5000 ip saddr 100.64.0.0/10 accept  # nix-serve (Tailscale)
    tcp dport 5000 ip saddr 192.168.178.0/24 accept # nix-serve (local LAN)
    tcp dport 6768 ip saddr 100.64.0.0/10 accept  # orca runtime server (Tailscale)
  ''
    + (import ../../lib).privateNetRules {
      tcp = [ "8080" "8888" "4000" ];  # strata + unsloth studio + litellm proxy
    };

  # LiteLLM proxy: the rank gateway all hosts' opencode/pi point at (see
  # services/litellm-proxy.nix for the config and docs/litellm-proxy-design.md
  # for the design).
  services.litellm-proxy.enable = true;

  # videoDrivers, the kernel and the driver package come from
  # ../../hardware/nvidia_ampere.nix, which laptop-p16 imports as well.

  # Dell 5810: no discrete Intel iGPU on the Xeon, so no prime offload needed.
  # The RTX 3060 (Ampere GA106, sm_86) is the only GPU. No power management on a
  # server — keep it at full boost for inference workloads.
  hardware.nvidia = {
    # NVIDIA RTX 3060 12GB (Ampere GA106, compute capability 8.6)
    dynamicBoost.enable = false; # desktop card, no dynamic boost
    gsp.enable = true; # NVIDIA GPU System Processor — offloads low-level GPU mgmt
    modesetting.enable = true; # Required for the NVIDIA driver
    nvidiaSettings = true;
    powerManagement = {
      enable = false; # Never sleep the GPU — inference server
      finegrained = false;
    };
    videoAcceleration = true;
  };

  # The NVIDIA module adds the out-of-tree kernel modules to
  # `boot.extraModulePackages` itself when "nvidia" is in videoDrivers, so no
  # host-level copy is needed here (a duplicate made the list contain the same
  # module package twice).

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
  # nvidia-container-toolkit is added from the module's own option so `nvidia-ctk`
  # on PATH is the exact build that generates the CDI spec.
  environment.systemPackages = [
    config.hardware.nvidia.package.bin
    config.hardware.nvidia-container-toolkit.package
  ];
}
