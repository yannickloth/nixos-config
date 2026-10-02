#!/usr/bin/env bash
# Package all agenix SSH private keys into a single PASSPHRASE-encrypted archive
# for backup.
#
# The archive (ssh-keys-backup-<date>.tar.gz.age) can be attached to a KeePassXC
# entry, or stored off-machine, so a wiped disk / reinstall can re-seed the keys
# and keep decrypting (and preserve syncthing device identity).
#
# It is encrypted with `age -p` (a passphrase you type, stored in KeePassXC),
# NOT to the SSH recipients: the archive contains those private keys, so
# encrypting it to them would be circular (you could not open the backup
# without a key that is inside it).
#
# To restore after a reinstall (you will be prompted for the passphrase):
#   age -d ssh-keys-backup-<date>.tar.gz.age | tar xzf -
#   # then copy each host/user private key back to its machine:
#   #   hosts/<name>        -> /etc/ssh/ssh_host_ed25519_key  (on that host)
#   #   users/<name>        -> ~/.ssh/agenix_<name>           (on that user's machine)
# See secrets-structure/README.md.

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="$REPO_DIR/ssh-keys"
OUT="$REPO_DIR/ssh-keys-backup-$(date +%Y%m%d).tar.gz.age"

if [[ ! -d "$SRC" ]]; then
  echo "error: no ssh-keys/ directory at $SRC" >&2
  exit 1
fi

# The age binary: from PATH (devShell) or fetched.
if command -v age >/dev/null 2>&1; then
  AGE=(age)
else
  AGE=(nix run nixpkgs#age --)
fi

umask 077
TMP_TAR="$(mktemp)"
trap 'rm -f "$TMP_TAR"' EXIT

tar -czf "$TMP_TAR" -C "$REPO_DIR" ssh-keys

echo "Contents:"
tar -tzf "$TMP_TAR"
echo

echo "Encrypting to $OUT (you will be asked for a passphrase)..."
"${AGE[@]}" -p -o "$OUT" "$TMP_TAR"
chmod 600 "$OUT"

echo
echo "Encrypted backup written: $OUT"
echo "Store the passphrase in KeePassXC and attach/store this file."
echo "Restore with: age -d '$OUT' | tar xzf -"
