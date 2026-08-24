{ ... }:

{
  # Automatic garbage collection via the native NixOS nix.gc option — the
  # single GC mechanism. (A previous custom systemd unit was removed: the
  # NixOS nix-gc module already defines systemd.services.nix-gc, so overriding
  # it produced conflicting definitions.)
  nix.gc = {
    automatic = true;
    dates = "weekly";
    randomizedDelaySec = "15min";
    # -d (--delete-old): also delete old profile generations, so the store is
    # actually freed (plain nix-collect-garbage keeps every generation and thus
    # most old store paths).
    options = "-d";
  };
}
