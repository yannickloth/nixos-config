{ config, lib, pkgs, ... }:

with lib;
{
  imports = [
    # Include the results of the hardware scan.
    # Run `nixos-generate-config --show-hardware-config > ...` after first boot
    # to get the real values for disk, swap, and mount options.
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

  # --- Motherboard ---
  # Gigabyte GA-B85-HD3 · Socket 1150 · Intel B85 · Q3 2014
  # --------------------------------------------------------
  # CPU   │ Intel Core i7-4771 (Haswell-R, Q4 2014) — 4C/8T, 3.5 GHz
  #       │ Base 3.5 / Turbo 3.9, AVX2, 8 MB L3, HD Graphics 4600
  #       │ EOL: peak of socket 1150; no CPU upgrade path
  # RAM   │ 4× DDR3 UDIMM, max 32 GB (4×8 GB), 1600 MHz
  #       │ No ECC, no RDIMM; DDR3L works at 1.5 V
  # PCIe  │ 1× PCIe 3.0 x16 (full), 1× PCIe 3.0 x16-phys/x4-electrical
  #       │ 2× PCIe 2.0 x1 — no SLI, no CXL, no native NVMe
  # SATA  │ 6× SATA III (6 Gbps) — no M.2 slot
  # BIOS  │ Basic UEFI (GOP), CGA legacy — GRUB over systemd-boot
  # LAN   │ Realtek RTL8111G · Audio: Realtek ALC887
  #       │ EOL: BIOS updates ceased ~2018, platform is dead

  # --- GPU / Display ---
  # RX 580 8GB (AMD) + Intel iGPU (optional fallback).
  # The `amdgpu` kernel module is auto-loaded by the kernel for GCN 1.0+;
  # enabling graphics is enough for both X11 and Wayland/Plasma.
  hardware.graphics.enable = true;

  # --- CPU (Haswell) ---
  # 4th-gen Intel: enable microcode + CPU refresh.
  hardware.cpu.intel.updateMicrocode = true;

  # --- Bootloader ---
  # B85 chipset supports basic UEFI but is safest with GRUB for mixed
  # legacy/UEFI installs. If your BIOS is set to UEFI-only, systemd-boot
  # works just as well; swap this block if you prefer it.
  boot.loader.grub = {
    enable = true;
    device = "nodev"; # UEFI or BIOS (GRUB handles both)
    efiSupport = true;
    useOSProber = true;
  };

  # --- Boot / Power ---
  # No laptop-specific power management (no thermald, no suspend-on-lid).
  # Instead, keep the desktop idle policies sensible for an always-on machine.
  services.logind.settings = {
    Login.HandleLidSwitch = "ignore";
    Login.HandleLidSwitchExternalPower = "ignore";
  };

  # --- ZRAM + Swap ---
  # 32 GB RAM is plenty, but zram still reduces disk wear for cache-heavy workloads.
  zramSwap.memoryPercent = 25; # 8 GiB compressed in RAM
  swapDevices = [{ device = "/swapfile"; size = 8192; }]; # 8 GiB disk overflow

  # --- Networking ---
  # DNS: same Tailscale-first resolver as the laptops.
  networking.networkmanager.insertNameservers = [
    "100.100.100.100"
    "1.1.1.3"
    "1.0.0.3"
  ];

  # --- Nix ---
  # 32 GB RAM -> faster parallel builds (12 jobs, all cores).
  roles.nix.maxJobs = 12;
  roles.nix.cores = 0;

  # --- Syncthing (reduced folder set — desktop-leto has limited disk) ---
  # The shared pool.nix syncs 37 folders to every laptop. Desktop-leto only
  # gets the small/metadata ones: kids folders, notes, FileDrop, and meta.
  # All photo/music/backup/finance folders are excluded to save disk space.
  services.syncthing.settings.folders = let
    pool = import ../../services/syncthing/pool.nix;
    selected = [
      "00-09 - Management and Meta"
      "sven"
      "aaron"
      "notes"
      "FileDrop"
      "christine"
    ];
  in lib.listToAttrs (
    map (label: {
      name = label;
      value = let f = pool.folders.${label}; in {
        inherit (f) id;
        label = label;
        type = "sendreceive";
        rescanIntervalS = 3600;
        versioning = { type = "staggered"; params.maxAge = "31536000"; };
        path = "${config.services.syncthing.dataDir}/${label}";
        devices = f.devices;
      };
    }) selected
  );

  # --- Kids / Parental ---
  # Apply the family kid-security / gaming policy (malcontent, apparmor profiles).
  services.malcontent.enable = true;
}
