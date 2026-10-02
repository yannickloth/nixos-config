#!/bin/sh
# Install the CachyOS-side host tuning for Strata on laptop-p16 (see README.md).
# Run with sudo. Idempotent.
#
#   sudo ./install.sh [--apply-hugepages]
#
# The hugetlb reservation is NOT applied live by default: reserving 44 GiB of
# contiguous 2 MiB pages while Strata already holds its ~40 GiB pinned arena can
# stall the machine in memory compaction. It is reserved by systemd-sysctl at
# boot instead (before Strata starts). Pass --apply-hugepages to force it now.
set -eu

here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)

install -Dm644 "$here/99-strata-hugepages.conf" /etc/sysctl.d/99-strata-hugepages.conf
install -Dm644 "$here/99-strata-memlock.conf"  /etc/security/limits.d/99-strata-memlock.conf
install -Dm644 "$here/user@.service.d/99-strata-memlock.conf" \
                /etc/systemd/system/user@.service.d/99-strata-memlock.conf

# Everything except vm.nr_hugepages is safe to apply live.
sysctl --system >/dev/null 2>&1 || true

case "${1:-}" in
  --apply-hugepages)
    # May take a while (and compact memory) while the arena is pinned.
    sysctl -w vm.nr_hugepages=22528
    ;;
  *)
    printf '%s\n' \
      "strata host tuning installed." \
      "The 22528-page hugetlb reservation applies at next boot (or run" \
      "  sudo sysctl -w vm.nr_hugepages=22528" \
      "now, accepting a possible stall). Re-login or reboot for the memlock limits."
    ;;
esac

systemctl daemon-reload
