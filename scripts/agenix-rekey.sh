#!/usr/bin/env bash
# agenix rekey helper: regenerate the `hosts` recipient group from ssh-keys/
# and re-encrypt every .age secret to its declared recipients.
#
# Use this whenever the host key set changes (e.g. adding a new host):
#   1. Generate the new host SSH key into ssh-keys/ (gitignored):
#        ssh-keygen -t ed25519 -N "" -C "host <name>" -f ssh-keys/hosts/<name>
#   2. Run (needs a host key to decrypt existing secrets, hence sudo):
#        sudo ./scripts/agenix-rekey.sh
#   3. Commit secrets.nix + the re-encrypted .age files.
#
# secrets.nix has no global "all" union: each secret lists its own recipients
# (see the strategy note there). This script only rebuilds the `hosts` group
# (used for host-wide system secrets and the login password hashes) from
# ssh-keys/hosts/*.pub. Private keys are distributed to their machines and
# backed up in KeePassXC (see secrets-structure/README.md).
#
# Requires the agenix CLI (nix run nixpkgs#agenix or via the devShell).

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SECRETS_NIX="$REPO_DIR/secrets.nix"
HOSTS_DIR="$REPO_DIR/ssh-keys/hosts"
# Any host private key lets the script decrypt existing .age files to rekey them.
IDENTITY="${AGENIX_IDENTITY:-/etc/ssh/ssh_host_ed25519_key}"

# Build the deduplicated list of host public keys (type + base64).
hosts_recipients=()
for f in "$HOSTS_DIR"/*.pub; do
  [[ -e "$f" ]] || continue
  hosts_recipients+=("$(awk '{print $1" "$2}' "$f")")
done
if [[ ${#hosts_recipients[@]} -gt 0 ]]; then
  mapfile -t hosts_recipients < <(printf '%s\n' "${hosts_recipients[@]}" | awk '!seen[$0]++')
fi

if [[ ${#hosts_recipients[@]} -eq 0 ]]; then
  echo "error: no SSH public keys found under ssh-keys/hosts/" >&2
  exit 1
fi

echo "Host recipients ($(hostname)):"
printf '  %s\n' "${hosts_recipients[@]}"

# Build the `hosts` list literal (4-space indented Nix strings; the keys must
# be quoted — base64 contains +// which are not valid in a bare Nix identifier).
hosts_list=""
for r in "${hosts_recipients[@]}"; do
  hosts_list+="    \"$r\""$'\n'
done

# Regenerate secrets.nix: keep the header comment and the named recipients
# (host-*/user-* = "..."), rewrite only the `hosts = [ ... ];` group.
awk -v hostlist="$hosts_list" '
  /^  hosts = \[/ { print "  hosts = ["; printf "%s", hostlist; print "  ];"; skip=1; next }
  skip && /^[[:space:]]*\]/ { skip=0; next }
  skip { next }
  { print }
' "$SECRETS_NIX" > "$SECRETS_NIX.tmp" && mv "$SECRETS_NIX.tmp" "$SECRETS_NIX"

echo "Rewrote the \`hosts\` group in secrets.nix."

echo "Re-encrypting all secrets to their declared recipients..."
if command -v agenix >/dev/null 2>&1; then
  agenix -r -i "$IDENTITY"
else
  nix run nixpkgs#agenix -- -r -i "$IDENTITY"
fi

echo "Done. Review secrets.nix + the re-encrypted .age files, then commit."
