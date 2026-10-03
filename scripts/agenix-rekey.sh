#!/usr/bin/env bash
# agenix rekey helper: rebuild the `hosts` recipient group in secrets.nix from
# ssh-keys/hosts/*.pub, then re-encrypt every secret to the recipients declared
# for it in secrets.nix.
#
# Use when the host key set changes (e.g. adding a host):
#   1. Drop the new host's public key into ssh-keys/hosts/<name>.pub
#      (generate it with: ssh-keygen -t ed25519 -N "" -C "host <name>" -f ssh-keys/hosts/<name>).
#   2. Run on an EXISTING host that holds a current host key (needs one to
#      decrypt the host-scoped secrets, hence sudo):
#        sudo ./scripts/agenix-rekey.sh
#      Do NOT run it on the new host: it cannot decrypt the existing secrets,
#      and its incomplete key set would be refused (see the removal guard).
#   3. Commit secrets.nix + the re-encrypted .age files.
#
# secrets.nix has no global "all" union: each secret lists its own recipients.
# This script re-encrypts each secret to its declared recipients, so a single
# host key is enough for the host-scoped secrets. A secret this host cannot
# decrypt — another host's Syncthing device identity, encrypted to that host
# only — is skipped with a warning; set those up on/for their owning host.
#
# Requires age + jq + nix-instantiate (all in the devShell).

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SECRETS_NIX="$REPO_DIR/secrets.nix"
SECRETS_DIR="$REPO_DIR/secrets"
HOSTS_DIR="$REPO_DIR/ssh-keys/hosts"
# A host private key that can decrypt the host-scoped secrets.
IDENTITY="${AGENIX_IDENTITY:-/etc/ssh/ssh_host_ed25519_key}"

# All relative Nix paths below (`import ./secrets.nix`) assume the repo root.
cd "$REPO_DIR"

# Temp workspace + cleanup on any exit (rewrite temp, secrets.nix backup, plaintext).
umask 077
TMPDIR="$(mktemp -d)"
cleanup() {
  rm -f "$SECRETS_NIX.tmp"
  rm -rf "$TMPDIR"
}
trap cleanup EXIT

for tool in age jq nix-instantiate; do
  command -v "$tool" >/dev/null 2>&1 || {
    echo "error: '$tool' not found on PATH (use 'nix develop')." >&2
    exit 1
  }
done

# Fail before touching anything if secrets.nix is already broken.
nix-instantiate --eval -E '(import ./secrets.nix)' >/dev/null 2>&1 || {
  echo "error: $SECRETS_NIX does not evaluate; fix it before rekeying." >&2
  exit 1
}

# --- 1. Rebuild the `hosts` group in secrets.nix -----------------------------
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

grep -qE '^[[:space:]]*hosts[[:space:]]*=[[:space:]]*\[' "$SECRETS_NIX" || {
  echo "error: no 'hosts = [ ... ];' group found in $SECRETS_NIX" >&2
  exit 1
}

# Safety: never silently DROP an existing host recipient. Otherwise running this
# on a host whose ssh-keys/hosts/ is incomplete would re-encrypt the host-scoped
# secrets to a reduced set and lock the other hosts out. The canonical
# host-scoped secret's publicKeys are the current host set. Fail CLOSED if it
# cannot be evaluated.
old_hosts_json="$(nix-instantiate --eval --json -E '(import ./secrets.nix)."syncthing-gui-password.age".publicKeys' 2>/dev/null)" || {
  echo "error: cannot evaluate the current host set from $SECRETS_NIX; aborting." >&2
  exit 1
}
old_hosts="$(printf '%s' "$old_hosts_json" | jq -r '.[]' | sort -u)"
new_hosts="$(printf '%s\n' "${hosts_recipients[@]}" | sort)"
removed="$(comm -23 <(printf '%s\n' "$old_hosts") <(printf '%s\n' "$new_hosts"))"
if [[ -n "$removed" ]]; then
  echo "refusing: the rebuilt hosts group would drop existing recipient(s):" >&2
  printf '  %s\n' "$removed" >&2
  if [[ "${ALLOW_HOST_REMOVAL:-0}" != "1" ]]; then
    echo "set ALLOW_HOST_REMOVAL=1 to override." >&2
    exit 1
  fi
fi

# Build the `hosts` list literal (4-space indented Nix strings; the keys must
# be quoted — base64 contains +// which are not valid in a bare Nix identifier).
hosts_list=""
for r in "${hosts_recipients[@]}"; do
  hosts_list+="    \"$r\""$'\n'
done

# Rewrite only the `hosts = [ ... ];` group; keep everything else verbatim.
# Handles both a multi-line group and a single-line `hosts = [ ... ];`.
cp "$SECRETS_NIX" "$TMPDIR/secrets.nix.bak"
awk -v hostlist="$hosts_list" '
  /^[[:space:]]*hosts[[:space:]]*=[[:space:]]*\[/ {
    print "  hosts = ["; printf "%s", hostlist; print "  ];"
    if ($0 ~ /\][[:space:]]*;/) next   # single-line group (possibly with trailing text)
    skip = 1; next
  }
  skip && /\][[:space:]]*;/ { skip = 0; next }   # multi-line terminator (own line or trailing)
  skip { next }
  { print }
' "$SECRETS_NIX" > "$SECRETS_NIX.tmp" && mv "$SECRETS_NIX.tmp" "$SECRETS_NIX"

# Validate the rewritten file; roll back on failure (never leave it corrupted).
if ! nix-instantiate --eval -E '(import ./secrets.nix)' >/dev/null 2>&1; then
  cp "$TMPDIR/secrets.nix.bak" "$SECRETS_NIX"
  echo "error: the rewritten $SECRETS_NIX does not evaluate; rolled back." >&2
  exit 1
fi
echo "Rewrote the \`hosts\` group in secrets.nix."

# --- 2. Re-encrypt every secret to its declared recipients -------------------
mapfile -t files < <(nix-instantiate --eval --json -E 'builtins.attrNames (import ./secrets.nix)' | jq -r '.[]')
if [[ ${#files[@]} -eq 0 ]]; then
  echo "error: no secrets parsed from secrets.nix (bad edit?)" >&2
  exit 1
fi

for f in "${files[@]}"; do
  src="$SECRETS_DIR/$f"
  [[ -f "$src" ]] || { echo "skip $f (no $src)"; continue; }

  if ! age -d -i "$IDENTITY" "$src" > "$TMPDIR/plain" 2>/dev/null; then
    echo "skip $f (not decryptable with $IDENTITY; likely another host's identity)"
    continue
  fi

  args=()
  while IFS= read -r k; do args+=(--recipient "$k"); done \
    < <(nix-instantiate --eval --json --argstr name "$f" -E '{ name }: (import ./secrets.nix).${name}.publicKeys' | jq -r '.[]')
  age "${args[@]}" -o "$src" "$TMPDIR/plain"
  echo "re-encrypted $f"
done

echo "Done. Review secrets.nix + the re-encrypted .age files, then commit."
