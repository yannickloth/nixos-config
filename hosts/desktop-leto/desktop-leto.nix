{ config, lib, pkgs, ... }:

with lib;
{
  imports = [
    # Include the results of the hardware scan (generated on real hardware).
    ./hardware-configuration.nix

    # Shared family-laptop module set (IVP; desktops get the same apps, games,
    # desktop stack, and security policies).
    ../../environments/family-laptop.nix

    # Desktop-specific stacks (Plasma + Wine for Windows games/compatibility).
    ../../desktop/plasma.nix
    ../../apps/wine.nix

    # commonHm.hostName: home-manager modules cannot reach
    # config.networking.hostName, so the host name is passed explicitly.
    {
      home-manager.users.aeiuno = {
        imports = [ ../../users/aeiuno/aeiuno-hm.nix ];
        commonHm.hostName = "desktop-leto";
      };
    }
    {
      home-manager.users.nicky = {
        imports = [ ../../users/nicky/nicky-hm.nix ];
        commonHm.hostName = "desktop-leto";
      };
    }
    {
      home-manager.users.sven = {
        imports = [ ../../users/sven/sven-hm.nix ];
        commonHm.hostName = "desktop-leto";
      };
    }
    {
      home-manager.users.aaron = {
        imports = [ ../../users/aaron/aaron-hm.nix ];
        commonHm.hostName = "desktop-leto";
      };
    }
    # Unsloth Studio on desktop-leto uses the native backend with Vulkan
    # (AMD Polaris RX 580 is not ROCm-supported; the container backend has
    # no Vulkan device passthrough). DataDir stays in home — no /data volume.
    {
      home-manager.users.nicky.unsloth-studio.backend = lib.mkForce "native";
    }
    # Pass Vulkan env var to the unsloth-studio systemd user service so
    # the installer and runtime use the correct llama.cpp backend on AMD.
    {
      home-manager.users.nicky.systemd.user.services.unsloth-studio.Service.Environment =
        [ "UNSLOTH_LLAMA_CPP_BACKEND=vulkan" ];
    }
  ];

  # In this file comes everything that is specific to this host.
  networking.hostName = "desktop-leto"; # Define your hostname.

  # Syncthing device name for this host (see services/syncthing/pool.nix).
  services.syncthing.self = "desktop-leto";

  # --- Optical Drive ---
  # HL-DT-ST DVDRAM GH24NSB0 · SATA DVD±RW · 24× CD-R / 16× DVD-R
  # /dev/sr0 · kernel module: sr_mod (already in boot.initrd.availableKernelModules)
  # EOL: DVD±RW drives are legacy; useful for occasional media install,
  #       game disc backups, or reading older physical media.
  #

  # --- Motherboard ---
  # Gigabyte GA-B85-HD3 · Socket 1150 · Intel B85 · Q3 2014
  # --------------------------------------------------------
  # CPU   │ Intel Core i7-4771 (Haswell-R, Q4 2014) — 4C/8T, 3.5 GHz
  #       │ Base 3.5 / Turbo 3.9, AVX2, 8 MB L3, HD Graphics 4600
  #       │ EOL: peak of socket 1150; no CPU upgrade path
  # RAM   │ 4× DDR3 UDIMM, 32 GB (8 GB each), 1600 MHz — pending
  #       │ No ECC, no RDIMM; DDR3L works at 1.5 V. Upgrade for LLM
  #       │ work (small models under ~10 GB quantized can run on CPU).
  # PCIe  │ 1× PCIe 3.0 x16 (full), 1× PCIe 3.0 x16-phys/x4-electrical
  #       │ 2× PCIe 2.0 x1 — no SLI, no CXL, no native NVMe
  # SATA  │ 6× SATA III (6 Gbps) — no M.2 slot
  # BIOS  │ Basic UEFI (GOP), CGA legacy — GRUB over systemd-boot
  # LAN   │ Realtek RTL8111G · Audio: Realtek ALC887
  # WiFi  │ Mercusys MA37BE · WiFi 7 (802.11be) + Bluetooth 5.4
  #       │ PCI-E 3.0 ×1 card (Realtek RTL8852BE chipset), ~4 W draw —
  #       │ negligible on the +12 V rail.
  #       │ EOL: BIOS updates ceased ~2018, platform is dead

  # --- GPU / Display ---
  # RX 580 8GB (AMD) + Intel iGPU (optional fallback).
  # The `amdgpu` kernel module is auto-loaded by the kernel for GCN 1.0+;
  # enabling graphics is enough for both X11 and Wayland/Plasma.
  hardware.graphics.enable = true;

  # --- Bootloader ---
  # UEFI boot via systemd-boot (matches the running system).
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # --- PSU ---
  # CoolerMaster RS460-PSAP-I3 · 460 W peak / 400 W continuous · +12 V rail
  # 300 W (25 A). Peak system draw: i7-4771 (84 W) + RX 580 (185 W) +
  # rest (~50 W) ≈ 319 W on the +12 V rail. The 400 W continuous rating
  # leaves ~80 W of margin — sufficient for gaming and local LLM inference.
  # Gaming pushes the GPU to its TDP wall; LLM inference via Vulkan pulls
  # 100–150 W on the GPU. Neither exceeds the PSU's envelope.
  # The real bottleneck for LLM work is the RAM: only sub-3 GB models fit
  # in 8 GB, with very short context and slow generation. 32 GB DDR3 has been
  # ordered; with that capacity 7B models (4-bit quantized ≈ 4–5 GB) can run
  # with most of the model offloaded to system RAM.

  # --- Boot / Power ---
  # This host imports environments/laptop.nix (via family-laptop.nix), so it
  # also gets that file's laptop policies: thermald, power-profiles-daemon,
  # zram (mkDefault 50% of RAM) and upower. They are not harmful here and zram
  # is genuinely useful on an 8 GB box with no second drive, so they are left
  # on rather than un-pinned per host. upower finds no battery and idles.
  # What matters here is keeping the machine out of the sleep states that upset
  # the Wi-Fi card, so the idle policies below stay deliberately simple.
  services.logind.settings = {
    Login.HandleLidSwitch = "ignore";
    Login.HandleLidSwitchExternalPower = "ignore";
  };

  # --- Suspend ---
  # The MT7925 (mt7925e) loses its firmware state over suspend-to-RAM on this
  # board: every resume logs `pci_pm_resume returns -110`, mac80211 reports
  # "Hardware became unavailable upon resume", the driver falls back to a full
  # chip reset + firmware reload and wpa_supplicant re-associates ~15 s later
  # (kernel bugzilla #220395; fix c182bfe944eb only lands in 7.4+/7.3.y).
  # A desktop does not need S3, so refuse the sleep verbs rather than paying a
  # Wi-Fi outage per suspend. Screen blanking/DPMS is unaffected.
  systemd.sleep.settings.Sleep = {
    AllowSuspend = false;
    AllowHibernation = false;
    AllowSuspendThenHibernate = false;
    AllowHybridSleep = false;
  };

  # --- Networking ---
  # DNS: same Tailscale-first resolver as the laptops.
  networking.networkmanager.insertNameservers = [
    "100.100.100.100"
    "1.1.1.3"
    "1.0.0.3"
  ];

  # mt7925e ships 802.11 power save enabled (`iw dev wlp2s0 get power_save`
  # reports "on") and it is a documented trigger for link drops and latency
  # spikes on MT7925 (Ubuntu #2170180, openwrt/mt76 #1108). Measured neutral on
  # this link so far, but keep it off — a desktop has no reason to save power
  # on its only uplink.
  networking.networkmanager.wifi.powersave = false;

  # Keep the card out of PCIe ASPM as well. This board currently disables ASPM
  # on every link (LnkCtl: ASPM Disabled), so this is insurance: a BIOS reset or
  # a kernel default change would otherwise re-expose the L1.2 bug where pings
  # to the AP spike to 0.4-2 s and TX retries sit at 30-50 % (Ubuntu #2170180).
  # Scoped to mt7925e so the GPU/SATA links keep whatever the firmware allows.
  boot.extraModprobeConfig = ''
    options mt7925e disable_aspm=1
  '';

  # The Bluetooth half of the MT7925 is a USB function of the same combo module
  # (13d3:3631). It currently sits in USB autosuspend (power/control=auto, 2 s),
  # which is exactly the kind of sleep state worth refusing on a desktop that
  # keeps its keyboard/mouse/gamepad bonded all day. hardware/bluetooth.nix only
  # pins Intel 8087 controllers, so the MediaTek part is covered here.
  services.udev.extraRules = ''
    ACTION=="add", SUBSYSTEM=="usb", ATTR{idVendor}=="13d3", ATTR{idProduct}=="3631", ATTR{power/control}="on"
  '';

  # Kernel stance for this card. The rule, not a snapshot - re-check it after
  # every `nix flake update`, because linux_zen follows nixpkgs on its own:
  #
  #   * 7.3.0 and 7.3.1 are UNSAFE. c4edf9e3e0e5 (merged in v7.3-rc1) sets the
  #     WM2 rx mask for a queue that has no NAPI, so mt7925e_mac_reset()
  #     NULL-derefs in napi_disable() and freezes the box. A reset happens on
  #     firmware errors and RX hangs too, not just on suspend, so the S3 refusal
  #     above does not cover this one.
  #     => acceptable: <= 7.2.x (predates the regression) or >= 7.3.2.
  #   * 7.3.2+ carries the fix c182bfe944eb. It does not fix resume: Yi Cong's
  #     "do not report resume failure after reset recovery" is not upstream yet,
  #     which is why S3 stays refused above. Irrelevant while S0ix/S3 are off.
  #   * Firmware comes from linux-firmware (20261019 at the time of writing) and
  #     the card loads the current MT7925 patch image, so a kernel switch does not
  #     change it; nothing to pin there.
  #
  # Nothing in this file pins a kernel: the hardening below (powersave off, no
  # ASPM, BT out of autosuspend, sleep verbs refused) is version-independent and
  # survives an update unchanged. Check the version with:
  #   nix eval --raw .#nixosConfigurations.desktop-leto.pkgs.linuxKernel.packages.linux_zen.kernel.version
  # If an update lands on 7.3.0/7.3.1, pin this host to linux_7_2 (or any attr
  # >= 7.3.2) in mkHost until the next update.

  # --- Nix ---
  # 8 GB RAM -> limit parallel builds to avoid OOM.
  roles.nix.maxJobs = 2;

  # nicky's Unsloth Studio (enabled for this host in desktop-leto.nix) is a
  # user service that must be up no matter who is logged in: without lingering
  # it dies with the last session of that user. packages/unsloth-studio/home.nix
  # states the requirement; every other host sets it, this one was missing it.
  users.users.nicky.linger = true;

  # --- Syncthing ---
  # The shared pool.nix (services/syncthing/pool.nix) is the single source of
  # truth: desktop-leto (2 TB disk) syncs all folders in the pool — exact same
  # access config as the laptops. The module derives the folder set from the
  # pool via selectFoldersForHost, so nothing is declared here.

  # --- Kids / Parental ---
  # Apply the family kid-security / gaming policy (malcontent, apparmor profiles).
  services.malcontent.enable = true;
}
