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

  # --- Motherboard ---
  # Gigabyte GA-B85-HD3 · Socket 1150 · Intel B85 · Q3 2014
  # --------------------------------------------------------
  # CPU   │ Intel Core i7-4771 (Haswell-R, Q4 2014) — 4C/8T, 3.5 GHz
  #       │ Base 3.5 / Turbo 3.9, AVX2, 8 MB L3, HD Graphics 4600
  #       │ EOL: peak of socket 1150; no CPU upgrade path
  # RAM   │ 1× DDR3 UDIMM, 8 GB, 1600 MHz (1 of 4 slots populated)
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

  # --- Bootloader ---
  # UEFI boot via systemd-boot (matches the running system).
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # --- Boot / Power ---
  # No laptop-specific power management (no thermald, no suspend-on-lid).
  # Instead, keep the desktop idle policies sensible for an always-on machine.
  services.logind.settings = {
    Login.HandleLidSwitch = "ignore";
    Login.HandleLidSwitchExternalPower = "ignore";
  };

  # --- Networking ---
  # DNS: same Tailscale-first resolver as the laptops.
  networking.networkmanager.insertNameservers = [
    "100.100.100.100"
    "1.1.1.3"
    "1.0.0.3"
  ];

  # --- Nix ---
  # 8 GB RAM -> limit parallel builds to avoid OOM.
  roles.nix.maxJobs = 2;

  # --- Syncthing (reduced folder set — desktop-leto has limited disk) ---
  # The shared pool.nix (services/syncthing/pool.nix) is the single source of
  # truth: desktop-leto is listed only in the small/metadata folders (kids
  # folders, notes, FileDrop, and meta). All photo/music/backup/finance folders
  # are excluded to save disk space. The module derives the folder set from the
  # pool via selectFoldersForHost, so nothing is declared here.

  # --- Kids / Parental ---
  # Apply the family kid-security / gaming policy (malcontent, apparmor profiles).
  services.malcontent.enable = true;
}
