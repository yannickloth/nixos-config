#!/usr/bin/env bash
# Warns the user with a pop-up before the daily session-limit lock (sven/aaron
# parental-controls time limit), then logs the session out at the lock time.
# Dialogs run in the background: they stay up until dismissed but never block
# the loop, so the logout always fires on schedule.
# Usage: session-limit-reminder.sh LOCK_AT [DIALOG] [INTERVALS]
set -u

LOCK_AT="${1:-22:00}"
DIALOG="${2:-kdialog}"
INTERVALS="${3:-1800,900,300}" # seconds before lock, e.g. 30/15/5 minutes

TITLE="Screen-time warning"

IFS=',' read -r -a IV <<<"$INTERVALS"
declare -a SHOWN=()

max_iv=0
for iv in "${IV[@]}"; do
  [ "$iv" -gt "$max_iv" ] && max_iv=$iv
done

# Show a dialog in the background: it stays up (must-click OK) but never blocks
# the loop, so the lock-time enforcement always runs even if a dialog is open.
show_dialog() {
  local mins=$1
  local msg
  if [ "$mins" -le 0 ]; then
    msg="Time's up! The computer is logging you out now. Good night!"
  else
    msg="Heads up! Your account will be locked at ${LOCK_AT} in ${mins} minutes. Please save your work!"
  fi
  if [ "$DIALOG" = kdialog ]; then
    kdialog --title "$TITLE" --icon dialog-warning --msgbox "$msg" &
  else
    zenity --info --title "$TITLE" --text "$msg" --width=420 &
  fi
}

# Wait for a graphical session before trying to show dialogs.
while [ -z "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ]; do sleep 10; done

while true; do
  now_s=$(date +%s)
  lock_s=$(date -d "today ${LOCK_AT}" +%s)
  if [ "$lock_s" -le "$now_s" ]; then
    # Time's up: terminate the session. malcontent's login rule then blocks the
    # account from logging back in until the next allowed window.
    show_dialog 0
    sleep 10
    loginctl terminate-session "${XDG_SESSION_ID:-}" 2>/dev/null \
      || loginctl terminate-user "$(id -un)" 2>/dev/null || true
    sleep 300
    continue
  fi
  remain=$((lock_s - now_s))

  # New day (far from the next lock): reset so today's thresholds fire again.
  if [ "$remain" -gt "$max_iv" ]; then
    SHOWN=()
  fi

  for iv in "${IV[@]}"; do
    already=0
    if [ "${#SHOWN[@]}" -gt 0 ]; then
      for s in "${SHOWN[@]}"; do
        [ "$s" = "$iv" ] && already=1
      done
    fi
    if [ "$remain" -le "$iv" ] && [ "$already" -eq 0 ]; then
      show_dialog $((remain / 60))
      SHOWN+=("$iv")
    fi
  done
  sleep 30
done
