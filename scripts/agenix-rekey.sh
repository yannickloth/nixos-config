#!/usr/bin/env bash
# agenix rekey helper: regenerate the recipient union from ssh-keys/ and
# re-encrypt every .age secret to all of them.
#
# Use this whenever the recipient set changes (e.g. adding a new host or user):
#   1. Generate the new host/user SSH key into ssh-keys/ (gitignored):
#        ssh-keygen -t ed25519 -N "" -C "host <name>" -f ssh-keys/hosts/<name>
#   2. Run:
#        ./scripts/agenix-rekey.sh
#   3. Commit secrets.nix + the re-encrypted .age files.
#
# The `all` union in secrets.nix is rebuilt from every ssh-keys/hosts/*.pub and
# ssh-keys/users/*.pub, so any host/user can decrypt any secret. Private keys
# are distributed to their machines and backed up in KeePassXC (see
# secrets-structure/README.md).
#
# Requires the agenix CLI (nix run nixpkgs#agenix or via the devShell).

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SECRETS_NIX="$REPO_DIR/secrets.nix"
HOSTS_DIR="$REPO_DIR/ssh-keys/hosts"
USERS_DIR="$REPO_DIR/ssh-keys/users"
# Any SSH private key here lets the script decrypt existing .age files to rekey them.
IDENTITY="${AGENIX_IDENTITY:-/etc/ssh/ssh_host_ed25519_key}"

# Build the list of recipient public keys (type + base64), deduplicated.
recipients=()
for f in "$HOSTS_DIR"/*.pub "$USERS_DIR"/*.pub; do
  [[ -e "$f" ]] || continue
  key="$(awk '{print $1" "$2}' "$f")"
  recipients+=("$key")
done
# Deduplicate preserving order.
mapfile -t recipients < <(printf '%s\n' "${recipients[@]}" | awk '!seen[$0]++')

if [[ ${#recipients[@]} -eq 0 ]]; then
  echo "error: no SSH public keys found under ssh-keys/hosts/ and ssh-keys/users/" >&2
  exit 1
fi

echo "Recipients ($(hostname)):"
printf '  %s\n' "${recipients[@]}"

# Regenerate the `all` union in secrets.nix from the discovered keys.
# The file is structured as: `all = [ ... ];` inside the let block.
awk -v new="$(printf '    %s\n' "${recipients[@]}")" '
  /^  all = \[/ { print "  all = ["; print new; print "  ];"; inall=1; next }
  inall && /^\];/ { inall=0; next }   # skip original closing
  inall { next }                       # skip old entries
  { print }
' "$SECRETS_NIX" > "$SECRETS_NIX.tmp" && mv "$SECRETS_NIX.tmp" "$SECRETS_NIX"

echo "Rewrote the \`all\` union in secrets.nix."

echo "Re-encrypting all secrets to the union..."
if command -v agenix >/dev/null 2>&1; then
  agenix -r -i "$IDENTITY"
else
  nix run nixpkgs#agenix -- -r -i "$IDENTITY"
fi

echo "Done. Review secrets.nix + the re-encrypted .age files, then commit."
