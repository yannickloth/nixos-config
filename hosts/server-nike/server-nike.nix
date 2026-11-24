{ config, lib, ... }:

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

    # Shared family-host module set (IVP, see environments/family-host.nix):
    # the same chassis-independent family policy the portables get via
    # family-laptop.nix — roles, KDE Plasma desktop stack, family services
    # (printing/scanning/avahi, samba, xRDP, Syncthing, nix-serve, podman,
    # postgres), kids' flatpak gating. server-nike is used daily as a desktop,
    # so it is a family host, not a bare server; keeping this shared instead
    # of hand-picking modules stops the drift from laptop-p16.
    ../../environments/family-host.nix

    # Host delta (like laptop-xps and desktop-leto): sddm.wayland = false for
    # the NVIDIA open driver — kwin_wayland spins on open NVIDIA KMS/drm-mode
    # paths. family-host's xserver.nix enables Plasma + sddm; this corrects
    # the NVIDIA bit.
    ../../desktop/plasma.nix

    # USB Wi-Fi dongles (two Realtek RTL8191SU/RTL8188SU sticks). Driven by
    # the in-tree r8712u staging driver, which only exists in kernels <= 6.12 -
    # see hardware/usb-wifi.nix for the kernel-update constraint.
    ../../hardware/usb-wifi.nix

    # LiteLLM rank gateway (services/litellm-proxy.nix): the single LLM
    # endpoint for opencode/pi on every host. Sits next to Unsloth Studio
    # (loopback) and reaches Strata on laptop-p16 over Tailscale. PostgreSQL
    # (its admin UI/virtual keys/spend ledger) comes from family-host's
    # services/postgresql.nix import.
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
  # This service runs before sync.mount to create /data/sync and set its
  # ownership/permissions. We reverse the dependency: the service wants the
  # mount (not the other way around). If sync.mount wanted this service, the
  # mount unit would be part of local-fs.target, and the service would chain
  # through basic → sockets → cups.socket → sysinit → local-fs.target,
  # creating a cycle that systemd resolves by deleting the mount unit.
  systemd.services.syncthing-nike-data-dir = {
    description = "Create the /data/sync bind source before /sync mounts";
    wants = [ "sync.mount" ];
    requires = [ "data.mount" ];
    wantedBy = [ "multi-user.target" ];
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

  # Strata runs on server-nike beside Unsloth Studio (both 12 GB sm_86 cards,
  # each host serves its own :8080). The hugepage pool and the locked-memory
  # limits below are gated on nicky's profile enabling Strata here.

  # Bootloader — keep 5 generations max to prevent EFI partition fill-up.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.loader.systemd-boot.configurationLimit = 5;

  # Timezone: roles/base.nix defaults to Europe/Luxembourg (Messancy sits on
  # the Belgian-Luxembourg border; same UTC offset as Brussels). No host pins
  # its own — single source, no mkForce conflict.

  # Dell 5810: 2× Xeon E5-2699C v4 (Broadwell-EP, 22C/44T) — parallel
  # builds with all cores.
  roles.nix.maxJobs = 16;
  roles.nix.cores = 0;

  # Strata's expert arena uses MAP_HUGETLB|MAP_HUGE_2MB and needs the whole mmap
  # covered (all-or-nothing, else it falls back to 4 KiB pages). 22528 * 2 MiB =
  # 44 GiB: the arena plus headroom, the value this host ran with on 2026-11-19
  # (its own settings.json calibration). Only reserve it while nicky's
  # home-manager profile enables Strata here; a fixed pool is parked RAM that
  # normal allocations cannot use, and Unsloth Studio runs beside Strata on this
  # 94 GiB host. laptop-p16 sets the same pool in its own host file.
  boot.kernel.sysctl."vm.nr_hugepages" =
    lib.mkIf (config.home-manager.users.nicky.strata.enable or false) 22528;

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

  # Same nftables backend as environments/laptop-firewall.nix (this used to
  # come from environments/server.nix): the scoped extraInputRules below are
  # nftables-only text — with the iptables default backend they are silently
  # inert — and the avahi/tor/sonos module assertions require nftables.
  # The base firewall itself is on by default.
  networking.nftables.enable = true;

  # Tailscale DERP fallback port (came from environments/server.nix; the
  # tailscale service itself arrives via roles/system.nix, imported by every
  # <host>-configuration.nix).
  networking.firewall.allowedUDPPorts = [ 41641 ];

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
