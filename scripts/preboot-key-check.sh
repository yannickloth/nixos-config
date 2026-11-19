#!/usr/bin/env bash
# preboot-key-check: prove the machine side of the age secret chain before
# the first flake rebuild/boot of a fresh host.
#
# Why this exists (secrets-structure/README.md, "Why a successful build is
# not a login guarantee"): nixos-rebuild's build only reads the flake source
# (the committed git tree). The private key is gitignored by design, so the
# build-time gates can only verify the PUBLIC half. If a flake system boots
# with the key missing or wrong, sshd-keygen generates a new random host key
# at /etc/ssh/ssh_host_ed25519_key (nixpkgs nixos-26.05, sshd.nix), agenix
# uses it as its identity, nothing decrypts, and every password login fails
# on every boot (the 2026-11-19 server-nike incident). A green build never
# substitutes for this check.
#
# Usage (on the target host, as root, from a repo checkout that contains
# the gitignored ssh-keys/ directory — i.e. the copy made from the key-store
# machine, not a fresh clone):
#   sudo scripts/preboot-key-check.sh [HOST]
#   HOST defaults to $(hostname).
#
# Checks:
#   1. the store keypair exists in this checkout (ssh-keys/hosts/$HOST{,.pub})
#   2. /etc/ssh/ssh_host_ed25519_key exists, non-empty, root:root, mode 0600
#   3. the installed key pairs with the tracked .pub
#   4. every secrets/passwords/*.hash.age (login-critical, host-key scoped)
#      decrypts with the installed key and holds a SHA-512 hash
#   5. info: how many .age files in the repo this key decrypts (the rest are
#      scoped to other hosts/users)
#
# Exit: 0 all pass, 1 findings.

set -u

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOST="${1:-$(hostname)}"
INSTALLED=/etc/ssh/ssh_host_ed25519_key
STORE_KEY="$REPO_DIR/ssh-keys/hosts/$HOST"
STORE_PUB="$REPO_DIR/ssh-keys/hosts/$HOST.pub"

FAILURES=0
fail() { echo "preboot-key-check: FAIL: $*" >&2; FAILURES=$((FAILURES + 1)); }
ok()   { echo "preboot-key-check: ok: $*"; }

# --- 1. the store keypair in this checkout ---------------------------------
if [ ! -f "$STORE_KEY" ]; then
  fail "$STORE_KEY not found — this checkout has no gitignored keystore. Copy ssh-keys/ from the key-store machine (a fresh clone cannot contain it), then re-run."
  exit 1
fi
if [ ! -f "$STORE_PUB" ]; then
  fail "$STORE_PUB not found — the tracked public key is missing from the checkout."
  exit 1
fi
ok "store keypair present for host '$HOST'"

# age resolution: PATH first, then the nixpkgs package. The nix fallback
# needs flake support + network — the same prerequisites as the
# nixos-rebuild that follows, so no new dependency is introduced.
AGE_BIN="$(command -v age || true)"
if [ -z "$AGE_BIN" ] && command -v nix >/dev/null 2>&1; then
  echo "preboot-key-check: age not on PATH; fetching nixpkgs#age via nix..."
  out="$(nix build nixpkgs#age --print-out-paths 2>/dev/null || true)"
  if [ -n "$out" ] && [ -x "$out/bin/age" ]; then
    AGE_BIN="$out/bin/age"
  fi
fi
if [ -z "$AGE_BIN" ]; then
  fail "age is not available (not on PATH, and 'nix build nixpkgs#age' failed — needs flake support and network). Install age, then re-run."
  exit 1
fi

# --- 2. the installed key: present, right owner and mode -------------------
if [ ! -s "$INSTALLED" ]; then
  fail "$INSTALLED is missing or empty. Install it BEFORE rebuilding:
    sudo install -m 0600 $STORE_KEY $INSTALLED
  Then re-run this check. Do not boot the flake system in this state: sshd-keygen would generate a new random host key there and all logins would fail on every boot."
  exit 1
fi
ok "$INSTALLED present"

if [ "$(id -u)" -eq 0 ]; then
  meta="$(stat -c '%U:%G %a' "$INSTALLED")"
  if [ "$meta" != "root:root 600" ]; then
    fail "$INSTALLED is '$meta', expected 'root:root 600' — sshd refuses group/world-readable host keys"
  else
    ok "permissions root:root 600"
  fi
else
  echo "preboot-key-check: info: not running as root — cannot verify owner/mode of $INSTALLED (must be root:root 600)"
fi

# --- 3. the installed key pairs with the tracked .pub -----------------------
pub_side="$(awk '{print $1" "$2; exit}' "$STORE_PUB")"
inst_side="$(ssh-keygen -y -f "$INSTALLED" 2>/dev/null | awk '{print $1" "$2; exit}')"
if [ -z "$inst_side" ]; then
  fail "cannot derive a public key from $INSTALLED — not a readable OpenSSH private key"
elif [ "$inst_side" != "$pub_side" ]; then
  fail "installed key does NOT pair with ssh-keys/hosts/$HOST.pub (it may be a freshly generated or installer key). Replace it:
    sudo install -m 0600 $STORE_KEY $INSTALLED
  Then re-run this check."
else
  ok "installed key pairs with ssh-keys/hosts/$HOST.pub"
fi

# --- 4. every password secret decrypts and holds a SHA-512 hash ------------
pw_total=0
for f in "$REPO_DIR"/secrets/passwords/*.hash.age; do
  [ -e "$f" ] || continue
  pw_total=$((pw_total + 1))
  if ! hash="$("$AGE_BIN" -d -i "$INSTALLED" "$f" 2>/dev/null)"; then
    fail "cannot decrypt $f with the installed key — logins for this secret would fail"
    continue
  fi
  case "$hash" in
    '$6$'*) ok "decrypts $(basename "$f") (SHA-512 hash)" ;;
    *)      fail "$f decrypts but does not start with \$6\$ — not a valid SHA-512 password hash" ;;
  esac
done
if [ "$pw_total" -eq 0 ]; then
  fail "no secrets/passwords/*.hash.age found in $REPO_DIR — wrong checkout root?"
fi

# --- 5. info: repo-wide decryptability of this key --------------------------
total=0
dec=0
while IFS= read -r f; do
  total=$((total + 1))
  if "$AGE_BIN" -d -i "$INSTALLED" "$f" >/dev/null 2>&1; then
    dec=$((dec + 1))
  fi
done < <(find "$REPO_DIR/secrets" -name '*.age' | sort)
echo "preboot-key-check: info: $dec of $total .age files in the repo decrypt with this key (the rest are scoped to other hosts/users)"

# --- verdict -----------------------------------------------------------------
if [ "$FAILURES" -ne 0 ]; then
  echo "preboot-key-check: $FAILURES check(s) FAILED — do not rebuild/boot until they pass." >&2
  exit 1
fi
echo "preboot-key-check: all checks passed for host '$HOST' — safe to nixos-rebuild."
