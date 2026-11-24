{ config, lib, pkgs, ... }:

let
  # Number of generations the boot menu shows (2 on hera's 511 MiB ESP,
  # 5 elsewhere). This doubles as the pruning floor: a menu entry whose
  # generation has been collected stays visible but cannot boot, because its
  # `init=` store path is gone. So never keep fewer generations than entries.
  bootLimit = config.boot.loader.systemd-boot.configurationLimit;
  keep = if bootLimit == null then 2 else bootLimit;

  # Generations younger than this are kept even beyond the floor, so a quiet
  # period does not shrink rollback history to the bare minimum.
  windowDays = 14;

  # Delete system generations older than `windowDays`, but never any of the
  # newest `keep` (nor the current generation). Written by hand rather than
  # with --delete-older-than because nix-collect-garbage has no way to combine
  # an age window with a count floor.
  prune = pkgs.writeShellApplication {
    name = "prune-system-generations";
    runtimeInputs = [ config.nix.package pkgs.coreutils pkgs.gawk ];
    text = ''
      profile=/nix/var/nix/profiles/system
      keep=${toString keep}
      cutoff=$(( $(date +%s) - ${toString windowDays} * 86400 ))

      # "gen date time current?" rows, newest generation first.
      mapfile -t rows < <(
        nix-env -p "$profile" --list-generations |
          awk '$1 ~ /^[0-9]+$/ { print $1, $2, $3, ($NF == "(current)" ? "current" : "-") }' |
          sort -k1,1nr
      )

      doomed=()
      for ((i = keep; i < ''${#rows[@]}; i++)); do
        read -r gen day clock current <<< "''${rows[$i]}"
        [[ $current == current ]] && continue
        (( $(date -d "$day $clock" +%s) < cutoff )) && doomed+=("$gen")
      done

      if (( ''${#doomed[@]} )); then
        nix-env -p "$profile" --delete-generations "''${doomed[@]}"
      fi
    '';
  };
in

{
  # Automatic garbage collection via the native NixOS nix.gc option — the
  # single GC mechanism. (A previous custom systemd unit was removed: the
  # NixOS nix-gc module already defines systemd.services.nix-gc, so overriding
  # it produced conflicting definitions.)
  nix.gc = {
    automatic = true;
    dates = "weekly";
    randomizedDelaySec = "15min";
    # Not -d: --delete-old ignores both the age window and the count floor and
    # keeps only the current generation. Pruning happens in ExecStartPre;
    # this then collects the store paths those generations were keeping alive.
    options = "";
  };

  # With configurationLimit = null every generation keeps an entry, so
  # collecting any would leave dead entries: only prune when it is set.
  systemd.services.nix-gc.serviceConfig.ExecStartPre =
    lib.mkIf (bootLimit != null) (lib.getExe prune);
}
