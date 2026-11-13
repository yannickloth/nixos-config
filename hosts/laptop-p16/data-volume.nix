# /data on laptop-p16: the second LUKS+btrfs volume (nvme0n1p1, fs UUID
# fbaa1e9e-…). This is the NixOS equivalent of hosts/laptop-p16/cachyos/
# automount-data.sh, which is what the current CachyOS install uses.
#
# Why it must exist: podman's graphroot is /data/containers/nicky
# (packages/unsloth-studio/container.nix, option podmanStorageRoot), because
# the ~10 GB Unsloth image does not fit on /. storage.conf is user-wide, so
# when /data is missing every `podman` command fails, not just Studio's unit.
#
# The LUKS keyfile is deliberately NOT in the Nix store: `environment.etc`
# copies text there world-readable, which would publish the key into
# /nix/store. It lives at /etc/luks/data.key instead, created and enrolled once
# per install:
#
#   sudo hosts/laptop-p16/cachyos/automount-data.sh --key-only
#
# That script is host-agnostic in this mode: it only generates the key and adds
# it to a LUKS keyslot, which is exactly what NixOS cannot do declaratively.
# The passphrase slot stays valid as the recovery path, and must stay.
{ config, lib, ... }:
{
  # systemd-cryptsetup-generator reads /etc/crypttab at boot; the identifier is
  # the mapper name CachyOS already uses, so both installs see the same device
  # name. `nofail` keeps a lost key from blocking the boot.
  environment.etc."crypttab".text = ''
    luks-bfece090-af9c-4962-89e9-061d799cf864 UUID=bfece090-af9c-4962-89e9-061d799cf864 /etc/luks/data.key luks,discard,nofail
  '';

  # By filesystem UUID rather than by mapper path: the mapper only exists after
  # the crypttab unit ran, and systemd resolves the by-uuid node then.
  # automount so a late unlock (or a keyfile created after boot) still resolves
  # on first access instead of leaving an empty /data on /.
  fileSystems."/data" = {
    device = "/dev/disk/by-uuid/fbaa1e9e-a163-43f7-9ea7-a3ba564e061b";
    fsType = "btrfs";
    options = [
      "noatime"
      "compress=zstd"
      "nofail"
      "x-systemd.automount"
      "x-systemd.device-timeout=10s"
    ];
  };
}
