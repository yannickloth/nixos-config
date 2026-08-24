{ ... }:

{
  # Automatic garbage collection via the native NixOS nix.gc option — the
  # single GC mechanism. (A previous custom systemd unit was removed: the
  # NixOS nix-gc module already defines systemd.services.nix-gc, so overriding
  # it produced conflicting definitions. nix-collect-garbage keeps the current
  # + rollback generations.)
  nix.gc = {
    automatic = true;
    dates = "weekly";
    randomizedDelaySec = "15min";
  };
}
