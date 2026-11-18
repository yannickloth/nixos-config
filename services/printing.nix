# Declarative CUPS queues that do not fail the activation when a printer is off.
#
# nixpkgs' `hardware.printers.ensurePrinters` generates one flat
# `ensure-printers.service` whose script runs `lpadmin … -E` for every queue
# under `set -e`. `lpadmin -E` probes the device, and when the printer is simply
# switched off it blocks for the full IPP connect timeout (~30 s), then fails:
#
#   - nixos-rebuild switch exits non-zero ("the following units failed"):
#     a rebuild "fails" for a reason unrelated to the system configuration;
#   - the queues declared after the dead one are never created;
#   - `ensureDefaultPrinter` is skipped;
#   - `systemctl stop cups.service` (startWhenNeeded) is skipped, so CUPS keeps
#     running until the next boot.
#
# This module keeps the declarative data exactly as nixpkgs defines it, but
# replaces the generated script. Each queue goes through `ensure-printer`
# (packages/printing/ensure-printers.nix), which:
#   - probes the printer's IPP port with a 1 s TCP connect first;
#   - on failure prints a WARNING naming the printer, its URI and the steps
#     skipped, and exits 0 (the unit succeeds);
#   - records the failure so `ensure-printers-retry.timer` retries every 15 min
#     until the printer answers (or the wrapper gives up after ~5 h).
#
# Exit status stays non-zero only when lpadmin fails against a REACHABLE device
# (bad model, bad URI, permissions) - that is a config error and should fail.
{ config, lib, pkgs, ... }:

let
  cfg = config.hardware.printers;

  # Built by packages/printing (one `ensure-printer` guard per queue plus the
  # default-printer step). A real derivation: systemd's `script` option runs it.
  ensurePrinters = pkgs.callPackage ../packages/printing/ensure-printers.nix {
    inherit (cfg) ensurePrinters ensureDefaultPrinter;
  };

  # nixpkgs appends this stop to its own script (startWhenNeeded). Same
  # condition, but only when at least one queue is managed here.
  keepCupsRunning = lib.optionalString (
    cfg.ensurePrinters != [ ]
    && config.services.printing.enable
    && config.services.printing.startWhenNeeded
    && !config.services.printing.stateless
  ) ''
    # Note: if cupsd is "stateless" the service can't be stopped, otherwise the
    # configuration would be wiped on the next start. Same condition nixpkgs uses.
    systemctl stop cups.service
  '';
in
{
  programs.system-config-printer.enable = true;
  services.ipp-usb.enable = true;
  services.printing = {
    cups-pdf.enable = true; # Enable CUPS to print documents.
    # canon-cups-ufr2 is built from a non-redistributable tarball via
    # requireFile: listing it here makes every fresh host fail the build until
    # the UFR II tarball is added manually (`nix-store --add-fixed sha256
    # linux-UFRII-drv-*.tar.gz`). No Canon printer is configured in this repo,
    # so it is left out; re-add it (and the manual download step) if a Canon
    # device is ever attached.
    # cups-pdf-to-pdf is already pulled in by cups-pdf above.
    drivers = with pkgs; [
      epson-escpr2
      brgenml1lpr
      brgenml1cupswrapper
      brlaser
      cups-filters
    ];
    enable = true;
  };

  # Two units on purpose: one at activation/boot, one periodic retry. They share
  # the same script, whose per-printer probe decides what still needs doing.
  # Same unit names as the nixpkgs module would generate; the second
  # definition's `mkForce` replaces that module's plain (priority 100) one.
  systemd.services.ensure-printers = lib.mkMerge [
    (lib.mkIf (cfg.ensurePrinters != [ ] && config.services.printing.enable) {
      description = "Ensure NixOS-configured CUPS printers";
      wantedBy = [ "multi-user.target" ];
      wants = [ "cups.service" ];
      after = [ "cups.service" ];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        # One 1 s probe per printer plus at most one 30 s lpadmin; this only
        # guards against a wedged cupsd.
        TimeoutStartSec = "3min";
      };
    })
    (lib.mkIf (cfg.ensurePrinters != [ ] && config.services.printing.enable) {
      # The override: without it nixpkgs' `script` (set -e, raw lpadmin) merges
      # with ours and the concatenation is not even valid Nix.
      # No cups-stop here: nixpkgs already appends it to this unit's script,
      # and two definitions concatenate. Only the start/stop of the queue
      # provisioning is ours, so the trailing stop lands exactly once.
      #
      # Note: `script` is used as the *body* of the generated unit wrapper,
      # and the package's store path is a directory — the executable lives
      # under /bin (writeShellApplication), so it must be named explicitly.
      script = lib.mkForce "${ensurePrinters}/bin/ensure-printers";
    })
  ];

  # Second chance for a queue whose printer was off at switch time: no rebuild
  # needed, just switch the printer on and wait for the next tick.
  systemd.services.ensure-printers-retry = lib.mkIf (cfg.ensurePrinters != [ ] && config.services.printing.enable) {
    description = "Retry CUPS queues that were skipped because the printer was offline";
    startAt = "*-*-* *:00/15:00";
    wants = [ "cups.service" ];
    after = [ "cups.service" ];
    serviceConfig = {
      Type = "oneshot";
      TimeoutStartSec = "5min";
    };
    script = "${ensurePrinters}/bin/ensure-printers" + "\n" + keepCupsRunning;
  };
}
