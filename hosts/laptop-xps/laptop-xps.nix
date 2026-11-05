{ config, lib, pkgs, ... }:

with lib;
{
  imports = [
    # Include the results of the hardware scan.
    ./hardware-configuration.nix

    # Shared family-laptop module set (IVP; see the file header for the deltas).
    ../../environments/family-laptop.nix

    # laptop-xps-only modules (SONOS controller + extra Plasma packages; the
    # 16 GiB host also runs the lighter Plasma session). apps/wine.nix puts
    # wine in PATH so Lutris's system check finds a default runner.
    ../../apps/noson.nix
    ../../apps/wine.nix
    ../../desktop/plasma.nix

    # commonHm.hostName: home-manager modules cannot reach
    # config.networking.hostName, so the host name is passed explicitly.
    {
      home-manager.users.aeiuno = {
        imports = [ ../../users/aeiuno/aeiuno-hm.nix ];
        commonHm.hostName = "laptop-xps";
      };
    }
    {
      home-manager.users.nicky = {
        imports = [ ../../users/nicky/nicky-hm.nix ];
        commonHm.hostName = "laptop-xps";
      };
    }
    {
      home-manager.users.sven = {
        imports = [ ../../users/sven/sven-hm.nix ];
        commonHm.hostName = "laptop-xps";
      };
    }
    {
      home-manager.users.aaron = {
        imports = [ ../../users/aaron/aaron-hm.nix ];
        commonHm.hostName = "laptop-xps";
      };
    }
  ];
  # In this file comes everything that is specific to this host.
  networking.hostName = "laptop-xps"; # Define your hostname.

  # nicky's per-user services must survive logout so Unsloth Studio's local
  # System One API (packages/unsloth-studio/home.nix) serves whoever is
  # logged in — same reason laptop-p16 lingers nicky (Orca runtime server).
  users.users.nicky.linger = true;

  # Rootless podman (the Unsloth Studio container backend) maps the user's
  # UIDs through /etc/subuid; nixpkgs' virtualisation.podman does not manage
  # these files, and without them a user's `podman run` fails with "no subuid
  # ranges found". Values match what was already on disk (manual step,
  # 2026-11-04), so this manages the existing files without remapping. The
  # other hosts get the same when their rootless storage is first created.
  environment.etc."subuid".text = ''
    nicky:100000:65536
    aeiuno:165536:65536
    sven:231072:65536
    aaron:296608:65536
  '';
  environment.etc."subgid".text = ''
    nicky:100000:65536
    aeiuno:165536:65536
    sven:231072:65536
    aaron:296608:65536
  '';

  # Syncthing device name for this host (see services/syncthing/pool.nix).
  services.syncthing.self = "laptop-xps";

  # 16 GiB RAM -> keep browser profiles on disk (psd disabled).
  roles.psd.enable = false;

  # Bootloader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # Btrfs swapfile on the root filesystem (in addition to zram) as disk-swap overflow.
  swapDevices = [{ device = "/swapfile"; size = 16384; }]; # 16 GiB; adjust to match RAM/disk

  # 16 GiB RAM -> 25% zram (shared default is 50%, sized for >=64 GiB hosts).
  # Keeps page cache RAM free while still giving compressed overflow on top of the swapfile.
  zramSwap.memoryPercent = 25;

  # Trim SSD (NVMe) weekly to keep free-space performance and endurance up.
  services.fstrim.enable = true;

  # DNS: the Tailscale resolver MUST stay first. It is the only resolver that
  # knows the .ts.net MagicDNS names (the peer nix-serve substituters in
  # roles/nix.nix), and glibc treats the first NXDOMAIN as final, so a public
  # resolver ahead of it made every peer name unresolvable. Behind it,
  # Cloudflare Family (1.1.1.3 / 1.0.0.3, blocks malware + adult content) is
  # the fallback. General queries are answered by the tailnet's upstream
  # resolver; to keep family-safe filtering on those too, set the tailnet's
  # custom resolver to 1.1.1.3/1.0.0.3 in the Tailscale admin console.
  # Note: DNS applies machine-wide, not per-user.
  networking.networkmanager.insertNameservers = [ "100.100.100.100" "1.1.1.3" "1.0.0.3" ];

  # Suspend on lid close. suspend-then-hibernate is NOT enabled because NixOS
  # cannot resume a hibernation image from a btrfs swapfile (no resume_offset
  # support) on this LUKS setup; it would need a dedicated swap partition.
  services.logind.settings.Login.HandleLidSwitch = "suspend";
  systemd.sleep.settings.Sleep = {
    HibernateDelaySec = "1h"; # ready for when a hibernation-capable swap partition is added
  };

  # 16 GiB RAM -> cap concurrent builds to avoid OOM during rebuilds (4 cores/8 threads).
  roles.nix.maxJobs = 4;
}
