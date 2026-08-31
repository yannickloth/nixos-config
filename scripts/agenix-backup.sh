#!/usr/bin/env bash
# Package all agenix SSH private keys into a single archive for backup.
#
# The archive (ssh-keys-backup-<date>.tar.gz) can be attached to a KeePassXC
# entry, or stored off-machine, so a wiped disk / reinstall can re-seed the
# keys and keep decrypting (and preserve syncthing device identity).
#
# To restore after a reinstall:
#   tar xzf ssh-keys-backup-<date>.tar.gz
#   # then copy each host/user private key back to its machine:
#   #   hosts/<name>        -> /etc/ssh/ssh_host_ed25519_key  (on that host)
#   #   users/<name>        -> ~/.ssh/agenix_<name>           (on that user's machine)
# See secrets-structure/README.md.

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="$REPO_DIR/ssh-keys"
OUT="$REPO_DIR/ssh-keys-backup-$(date +%Y%m%d).tar.gz"

if [[ ! -d "$SRC" ]]; then
  echo "error: no ssh-keys/ directory at $SRC" >&2
  exit 1
fi

tar -czf "$OUT" -C "$REPO_DIR" ssh-keys

echo "Backup written: $OUT"
echo "Attach this file to a KeePassXC entry (or store it offline)."
echo
echo "Contents:"
tar -tzf "$OUT"
