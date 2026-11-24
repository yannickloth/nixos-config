# Offline-aware CUPS queue provisioning.
#
# Renders the `hardware.printers.ensurePrinters` data into a shell script where
# every queue is created through `ensure-printer`, which warns instead of failing
# when the printer is switched off. See services/printing.nix for the rationale.
#
# Kept as its own file so the flake check `printing-script` can run the real
# script and the offline path of the wrapper in the build sandbox.
{
  lib,
  writeShellApplication,
  bash,
  coreutils,
  cups,
  ensurePrinters,
  # The nixpkgs submodule type declares `location`/`description` as
  # nullOr str (they end up as "null" in `lpadmin -L` if not given); callers
  # pass "" for "unset". shellcheck also reads them, hence the clean strings.
  ensureDefaultPrinter ? null,
  # Budget for one TCP probe of the printer's IPP port. A switched-off printer
  # drops the SYN, so this is what turns a 30 s lpadmin timeout into a short
  # probe; 3 s because a deep-sleeping Brother laser needs a moment to wake
  # before the connect completes (with the old 1 s it was declared off at
  # every switch time on server-nike, 2026-11-24, despite being up seconds
  # later under a 3 s probe).
  probeTimeout ? 3,
  # The wrapper gives up (and stops the retry timer) after this many failed
  # probes, i.e. ~5 h at the timer's 15 min cadence.
  maxAttempts ? 20,
}:

let
  # --- the per-printer guard -------------------------------------------------

  # `ensure-printer NAME URI MODEL DESC LOC` creates/refreshes one queue and
  # never fails because the device is off. It fails only if lpadmin fails while
  # the device IS reachable (bad model, bad URI, permissions) - a real config
  # error that should fail the unit.
  ensurePrinter = writeShellApplication {
    name = "ensure-printer";
    # bash for the /dev/tcp probe, coreutils for timeout and sleep — neither
    # may come from the inherited PATH: the systemd unit's default PATH has
    # coreutils but no bash, so `bash -c` inside the probe failed with
    # "command not found" (stderr eaten by the probe's 2>/dev/null) and every
    # printer was declared off or unreachable — on real systems only; the
    # flake check never saw it because the build sandbox has bash on PATH.
    runtimeInputs = [ bash coreutils cups ];
    text = ''
      set -uo pipefail
      NAME=$1; DEVICE=$2; MODEL=$3; DESC=$4; LOC=$5

      # Retry bookkeeping, per printer. XDG_RUNTIME_DIR is set for user units and
      # absent for system ones, where /run is the equivalent.
      state_dir="''${XDG_RUNTIME_DIR:-/run}/ensure-printers"
      state="$state_dir/$NAME.attempts"
      mkdir -p "$state_dir"
      attempts=$(cat "$state" 2>/dev/null || echo 0)

      # Strip the scheme, then the path: ipp://host/ppd, ipps://host:631/ipp/print
      authority=''${DEVICE#*://}
      authority=''${authority%%/*}
      scheme=''${DEVICE%%:*}
      case "$authority" in
        *:*) host=''${authority%:*}; port=''${authority##*:} ;;
        *)   host=$authority; port=631 ;;
      esac

      skip() {
        printf 'WARNING: printer %s (%s) is off or unreachable\n' "$NAME" "$DEVICE" >&2
        printf '         skipped: queue not created/refreshed, default printer not changed\n' >&2
        attempts=$((attempts + 1))
        echo "$attempts" > "$state"
        if [ "$attempts" -ge ${toString maxAttempts} ]; then
          printf 'ERROR: giving up on %s after %s attempts - switch it on and rerun: sudo systemctl restart ensure-printers\n' \
            "$NAME" "$attempts" >&2
          systemctl stop ensure-printers-retry.timer 2>/dev/null || true
        else
          printf '         retry %s/%s in 15 min (ensure-printers-retry.timer)\n' \
            "$attempts" ${toString maxAttempts} >&2
        fi
        exit 0
      }

      # Only network printers are probed. Local/spooler URIs (cups-pdf:/pdf,
      # usb://..., hp:/...) have no IPP endpoint and must never be skipped.
      # Three tries with a pause: a Wi-Fi printer in power save (the Brother
      # answers pings at ~8 ms, then vanishes for seconds at a time) fails one
      # connect and answers the next; a genuinely off printer fails all of
      # them and the whole loop still costs ~13 s.
      case "$scheme" in
        ipp|ipps|http|https)
          probe_ok=""
          for _ in 1 2 3; do
            if timeout "${toString probeTimeout}" bash -c \
              "exec 3<>/dev/tcp/$host/$port" 2>/dev/null; then
              probe_ok=1
              break
            fi
            sleep 2
          done
          [ -n "$probe_ok" ] || skip
          ;;
      esac

      lpadmin -p "$NAME" -v "$DEVICE" -m "$MODEL" -D "$DESC" -L "$LOC" -E
      rm -f "$state"
    '';
  };

  # --- the queue list --------------------------------------------------------

  mkEnsure =
    p:
    lib.escapeShellArgs [
      "${ensurePrinter}/bin/ensure-printer"
      p.name
      p.deviceUri
      p.model
      (p.description or "")
      p.location
    ];

  # The extra steps nixpkgs appends after the queues (default printer, and
  # stopping cupsd when it is started on demand).
  tail = lib.optionalString (ensureDefaultPrinter != null) ''
    # Only make it the default if the queue actually exists, otherwise a dead
    # printer would leave no usable default.
    if ${cups}/bin/lpstat -p ${lib.escapeShellArg ensureDefaultPrinter} >/dev/null 2>&1; then
      ${cups}/bin/lpadmin -d ${lib.escapeShellArg ensureDefaultPrinter}
    else
      echo "WARNING: default printer ${ensureDefaultPrinter} not configured (printer off?) - keeping current default" >&2
    fi
  '';
in
writeShellApplication {
  name = "ensure-printers";
  runtimeInputs = [ cups ];
  # Exposed so the flake check `printing-script` can drive the offline path of
  # one guard without going through a full queue list.
  passthru.ensurePrinter = "${ensurePrinter}/bin/ensure-printer";
  text = ''
    set -uo pipefail

    ${lib.concatMapStringsSep "\n" mkEnsure ensurePrinters}

    ${tail}
  '';
  # nixpkgs' own cups-pdf queue carries a literal ${USER} in its location
  # (it is expanded by cupsd, not by the shell). SC2016 is about the intent
  # being unclear; here it is intentional.
  excludeShellChecks = [ "SC2016" ];
}
