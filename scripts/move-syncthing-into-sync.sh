#!/usr/bin/env bash
# Move aeiuno's old syncthing content into the system /sync tree, merging each
# folder that already exists under the destination (default /sync/christine).
# Ownership is set to syncthing:syncthing in place, then preserved by the move
# (same-filesystem moves are instant renames). Dry-run by default; pass
# --apply to execute. Run as root, with both syncthing daemons stopped.
#
#   sudo systemctl stop syncthing                       # system service
#   systemctl --user stop syncthing                     # aeiuno's temporary one
#   sudo SRC_ROOT=/home/aeiuno/syncthing/christine \
#        ./move-syncthing-into-sync.sh                   # dry-run
#   sudo SRC_ROOT=... ./move-syncthing-into-sync.sh --apply
set -euo pipefail

SRC_ROOT="${SRC_ROOT:-/home/aeiuno/syncthing/christine}"
DST_ROOT="${DST_ROOT:-/sync/christine}"
OWNER="${OWNER:-syncthing:syncthing}"

APPLY=0
for arg in "$@"; do
  case "$arg" in
    --apply) APPLY=1 ;;
    -h|--help) sed -n '2,13p' "$0"; exit 0 ;;
    *) echo "unknown argument: $arg" >&2; exit 2 ;;
  esac
done

[[ $EUID -eq 0 ]] || { echo "error: run as root" >&2; exit 1; }
[[ -d $SRC_ROOT ]] || { echo "error: no source dir: $SRC_ROOT" >&2; exit 1; }
[[ -d $DST_ROOT ]] || { echo "error: no destination dir: $DST_ROOT" >&2; exit 1; }
if systemctl is-active --quiet syncthing; then
  echo "error: system syncthing is running; stop it first" >&2
  exit 1
fi

run() { if ((APPLY)); then "$@"; else printf 'DRY: '; printf '%q ' "$@"; printf '\n'; fi; }

echo "$SRC_ROOT -> $DST_ROOT (owner $OWNER)"
run chown -R "$OWNER" "$SRC_ROOT"

shopt -s dotglob nullglob
for dst in "$DST_ROOT"/*; do
  [[ -d $dst ]] || continue
  name="$(basename "$dst")"
  src="$SRC_ROOT/$name"
  if [[ ! -e $src ]]; then
    echo "skip  $name (no counterpart in source)"
    continue
  fi
  if [[ -d $src ]]; then
    echo "merge $src -> $dst"
    for item in "$src"/*; do
      run mv -n -- "$item" "$dst/"
    done
    run rmdir --ignore-fail-on-non-empty "$src" 2>/dev/null || true
  else
    echo "move  $src -> $DST_ROOT"
    run mv -n -- "$src" "$DST_ROOT/"
  fi
done
