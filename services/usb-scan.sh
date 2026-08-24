#!/usr/bin/env bash
# ClamAV scan of an inserted USB drive (device name passed as $1, e.g. "sdb1").
# Mounts it read-only if not already mounted, scans with clamdscan, and reports
# the result to the active desktop user + the journal. Report-only: infected
# files are listed, never deleted.
set -u

DEV="$1"
DEVICE="/dev/$DEV"

notify() {
  local icon="$1" summary="$2" body="$3" sess uid
  for sess in $(loginctl list-sessions --no-legend 2>/dev/null | awk '{print $1}'); do
    [ "$(loginctl show-session "$sess" -p State --value 2>/dev/null)" = "active" ] || continue
    uid=$(loginctl show-session "$sess" -p User --value 2>/dev/null) || continue
    [ -n "$uid" ] || continue
    export XDG_RUNTIME_DIR="/run/user/$uid"
    export DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$uid/bus"
    sudo -u "#$uid" notify-send -i "$icon" -a "USB scan" "$summary" "$body" 2>/dev/null
  done
}

# Give udisks2/KDE a moment to mount it (read-only per the udev rule).
sleep 3

MP=$(findmnt -rn -S "$DEVICE" -o TARGET 2>/dev/null | head -n1)
MOUNTED_US=0
if [ -z "$MP" ]; then
  MP="/run/usbscan/$DEV"
  mkdir -p "$MP"
  if ! mount -o ro "$DEVICE" "$MP" 2>/dev/null; then
    notify dialog-error "USB scan failed" "Could not mount $DEVICE read-only for scanning."
    exit 0
  fi
  MOUNTED_US=1
fi

OUT=$(clamdscan -r --no-summary "$MP" 2>&1)
RC=$?

if [ "$MOUNTED_US" -eq 1 ]; then
  umount "$MP" 2>/dev/null
  rmdir "$MP" 2>/dev/null
fi

case "$RC" in
  0)
    notify dialog-information "USB drive clean" "$DEV scanned: no threats found."
    ;;
  1)
    INFECTED=$(printf '%s\n' "$OUT" | grep -i "FOUND" || true)
    notify dialog-warning "USB drive: threats found" "$INFECTED"
    echo "USB scan $DEVICE found threats:" >&2
    printf '%s\n' "$INFECTED" >&2
    ;;
  *)
    notify dialog-error "USB scan error" "ClamAV scan of $DEV failed (exit $RC)."
    echo "USB scan $DEVICE failed (exit $RC):" >&2
    printf '%s\n' "$OUT" >&2
    ;;
esac
