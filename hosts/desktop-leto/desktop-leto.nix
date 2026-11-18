{ config, lib, pkgs, ... }:

with lib;

let
  # fancontrol config — see the "--- Fan control ---" section below.
  fanConfig = ''
    # desktop-leto — GA-B85-HD3: IT8728F (hwmon3) + coretemp (hwmon1).
    # Identified on this machine 2026-11-18: pwm1 drives the CPU_FAN header
    # (fan1, the loud one) — its hardware curve is bound to the CPU PECI
    # temperature; pwm2/pwm3 are chassis-thermistor case-fan headers.
    #
    # The zen-kernel it87 driver switches this chip to manual mode when
    # fancontrol writes 1 to pwm1_enable (kernel docs, Documentation/hwmon/
    # it87.rst: "if you want to go for manual mode just write 1 to
    # pwmN_enable"); fancontrol 3.6.2 does exactly that. Writing 0 instead
    # means "on/off" mode, where the duty register is locked (EBUSY).
    #
    # Curve (i7-4771, 84 W, stock cooler): near-silent below 45 C (the fan's
    # practical minimum is ~974 RPM even at 0 % duty), full speed at 75 C —
    # well below the 100 C throttle point.
    INTERVAL=10
    DEVPATH=hwmon1=devices/platform/coretemp.0 hwmon3=devices/platform/it87.2608
    DEVNAME=hwmon1=coretemp hwmon3=it8728
    FCTEMPS=hwmon3/device/pwm1=hwmon1/temp1_input
    FCFANS=hwmon3/device/pwm1=hwmon3/device/fan1_input
    MINTEMP=hwmon3/device/pwm1=45
    MAXTEMP=hwmon3/device/pwm1=75
    MINSTART=hwmon3/device/pwm1=60
    MINSTOP=hwmon3/device/pwm1=15
    MINPWM=hwmon3/device/pwm1=0
    MAXPWM=hwmon3/device/pwm1=255
  '';
in
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
  # RAM   │ 2×8 GB TimTec DDR3 1600 MHz CL11-11-11-28, 1.5 V
  #       │ (standard DDR3, confirmed not DDR3L 1.35 V)
  #       │ 2Rx8 (dual-rank, x8 chip density)
  #       │ Part #: 75TT16NU2R8GRN-8G · Batch: PR260817ED#NP15
  #       │ Installed in slots 1 & 2 only — slots 3 & 4 are dead;
  #       │ no configuration (1×8, 2×8, 3×8, 4×8) POSTs with DIMMs
  #       │ in slots 3/4. 4×8GB (all slots) also does not POST.
  #       │ B85 chipset hard cap: 4× DIMM, 8 GB per slot, 32 GB
  #       │ total. 2×16 GB DIMMs do not POST (confirmed). No
  #       │ upgrade path within this platform; a new motherboard
  #       │ + DDR5 is required for 64 GB+. No ECC, no RDIMM.
  #       │ LLM work: ~5 GB models at 4-bit quantized fit with
  #       │ ~10 GB for context + headroom, but generation is slow
  #       │ on CPU.
  # PCIe  │ 1× PCIe 3.0 x16 (full), 1× PCIe 3.0 x16-phys/x4-electrical
  #       │ 2× PCIe 2.0 x1 — no SLI, no CXL, no native NVMe
  # SATA  │ 6× SATA III (6 Gbps) — no M.2 slot
  # BIOS  │ Basic UEFI (GOP), CGA legacy — GRUB over systemd-boot
  # LAN   │ Realtek RTL8111G · Audio: Realtek ALC887
  # WiFi  │ Mercusys MA37BE · WiFi 7 (802.11be) + Bluetooth 5.4
  #       │ PCI-E 3.0 ×1 card (Realtek RTL8852BE chipset), ~4 W draw —
  #       │ negligible on the +12 V rail.
  #       │ EOL: BIOS updates ceased ~2018, platform is dead
  #
  # --- Upgrades (4 paths) ---
  # 1. USB 3.2 Gen 2 (10 Gbps) PCIe x1 card with USB-C — targeted at
  #       an HP G5 docking station: the card's USB-C output feeds the
  #       dock's USB-C upstream; a USB-C selector switch sits between
  #       card and dock so mouse + keyboard (and any other docked
  #       peripherals) toggle between desktop-leto and the laptop.
  #       Gen 2 is the fastest standard that makes sense here —
  #       Gen 2x2 (20 Gbps) is overkill on a PCIe 3.0 x1 slot and
  #       cheap cards are unreliable. Choose an ASMedia ASM2142 or
  #       ASM1142 controller (good Linux xhci-pci support, avoid
  #       Fresco Logic which can be finicky on older kernels).
  # 2. GPU — AMD RX 580 8 GB (ordered). Replaces headless iGPU-only
  #       setup; enables gaming, desktop compositing, and Vulkan
  #       acceleration for Unsloth Studio (see VM passthrough section).
  # 3. CPU — upgrade i7-4771 (3.5 GHz base / 3.9 GHz turbo) to a
  #       4.0 GHz+ Haswell part (e.g. i7-4960X 3.6/4.0 GHz or
  #       i7-4771 itself at 3.5/3.9 — the 4771 already has the
  #       highest stock turbo for a locked B85 build). Overclocking
  #       is impossible on the B85 (non-Z chipset). Limited gain on
  #       a platform this old.
  # 4. CXL/PCIe-to-DDR4 extension card — experimental. A CXL 2.0
  #       expansion card (e.g. Marvell-based) lets a PCIe 3.0 x16
  #       host attach 8× DDR4 UDIMMs as memory expansion. Feasible
  #       on this board's x16 slot; latency is higher than native,
  #       and the DDR4 dies must be compatible with the CXL memory
  #       controller. See:
  #       https://videocardz.com/newz/new-cxl-2-0-card-lets-ddr5-servers-reuse-eight-ddr4-memory-modules
  #       Would let repurpose the 32 GB DDR3 into a new DDR4/DDR5
  #       system and squeeze an extra 64 GB (or more) out of this
  #       board as temporary LLM RAM. Untested on consumer B85 —
  #       these cards target Xeon/E5 server platforms.

  # --- GPU / Display ---
  # RX 580 8GB (AMD) + Intel iGPU (optional fallback).
  # The `amdgpu` kernel module is auto-loaded by the kernel for GCN 1.0+;
  # enabling graphics is enough for both X11 and Wayland/Plasma.
  hardware.graphics.enable = true;

  # --- Fan control ---
  # The stock Intel cooler on the i7-4771 is the loudest part of the box.
  # fancontrol (lm_sensors, installed in roles/system.nix) drives pwm1 — the
  # CPU_FAN header on the IT8728F Super I/O chip — from the coretemp curve
  # in `fanConfig` above. The chip leaves its BIOS auto curve and follows the
  # software one; the CPU runs a few degrees warmer but stays far below the
  # 100 °C throttle point, so there is no performance cost — only less noise.
  #
  # The `it87` module is loaded at boot so the hwmon interface exists for
  # fancontrol (and `sensors`). If the module or the fancontrol service is
  # ever missing, the chip simply stays on its BIOS auto curve — safe by
  # default, just louder.
  #
  # Tune: adjust MINTEMP/MAXTEMP/MINSTART/MINSTOP in fanConfig, then
  # `sudo nixos-rebuild switch`. Check state with `sensors` (fan1 = CPU fan)
  # and `systemctl status fancontrol`.
  hardware.fancontrol.config = fanConfig;
  hardware.fancontrol.enable = fanConfig != "";

  # Super I/O chip driver (fan headers + hwmon readings for this board).
  boot.kernelModules = [ "it87" ];

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
  # The real bottleneck for LLM work is the RAM: 32 GB is the B85 hard cap
  # (no DIMM-slot upgrade path). 7B models at 4-bit quantized (≈4–5 GB) fit
  # with comfortable context headroom, but generation is slow on the i7-4771.
  # Beyond 32 GB requires a full platform replacement (motherboard + DDR5).

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
  # 32 GB RAM -> 4 parallel builds safe (no OOM risk on this workload).
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
