#!/usr/bin/env bash
# age-audit: verify that age-encrypted secrets match the recipients declared
# in secrets.nix.
#
# Modes:
#   age-audit.sh repo [KEYSTORE_DIR]
#       Audit every secret listed in secrets.nix (repo root = this script's
#       parent). With KEYSTORE_DIR (e.g. the repo's ssh-keys/), additionally:
#       - every host keypair is paired (ssh-keygen -y reproduces the .pub)
#       - every secret decrypts with at least one key-store host key
#
#   age-audit.sh host SPEC_FILE
#       Audit the secrets one host consumes (used by the build-time per-host
#       probe in services/host-age.nix). SPEC_FILE lines:
#           <age-file> <pubkey> <pubkey> ...
#       No nix required in this mode.
#
# Recipient identity: the age v1 header carries, per SSH recipient, a
# 6-character fingerprint = base64(sha256(ssh_wire_pubkey)[:4]) without
# padding, as the stanza argument (see FiloSottile/age,
# agessh.sshFingerprint + internal/format). We recompute it for each declared
# public key and require exact set equality with the file's header. The
# authoritative check is still real decryption at activation, guarded by
# systemd age-secrets-guard; this audit catches configuration drift at build
# time, before anything is deployed.
#
# Exit: 0 clean, 1 findings.

set -u

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SECRETS_NIX="$REPO_DIR/secrets.nix"
SECRETS_DIR="$REPO_DIR/secrets"

FAILURES=0

fail() { echo "age-audit: FAIL: $*" >&2; FAILURES=$((FAILURES + 1)); }
ok()   { echo "age-audit: ok: $*"; }

# --- recipient fingerprint ---------------------------------------------------
# $1: "ssh-ed25519 <b64> [comment]"; prints the 6-char fingerprint.
fp_of_pub() {
    local b64
    b64="$(printf '%s\n' "$1" | awk '{print $2}')"
    if [ -z "$b64" ]; then
        echo ""
        return 1
    fi
    printf '%s' "$b64" | base64 -d 2>/dev/null \
        | openssl dgst -sha256 -binary 2>/dev/null \
        | head -c 4 \
        | base64 -w0 2>/dev/null | tr -d '='
}

# $1: age file; prints one fingerprint per SSH recipient stanza.
file_fps() {
    grep -aE '^-> (ssh-ed25519|ssh-rsa) ' "$1" 2>/dev/null | awk '{print $3}'
}

# $1: age file, $2: file with one declared pubkey per line (full "ssh-ed25519
# <b64>" strings — they contain a space, so they must not be word-split).
check_file() {
    local file=$1 keysfile=$2
    local base; base="$(basename "$file")"

    [ -f "$file" ] || { fail "$base: file not found ($file)"; return; }
    head -1 "$file" | grep -qa '^age-encryption.org/v1' \
        || { fail "$base: not an age-encryption.org/v1 file"; return; }

    local -a pubs=()
    while IFS= read -r p; do [ -n "$p" ] && pubs+=("$p"); done < "$keysfile"

    local declared actual missing extra
    declared=""
    local p
    for p in "${pubs[@]}"; do declared+="$(fp_of_pub "$p")"$'\n'; done
    declared="$(printf '%s' "$declared" | grep -v '^$' | sort -u)"
    actual="$(file_fps "$file" | sort -u)"

    # Parse sanity: every SSH stanza must carry the 6-char fingerprint token.
    # (process substitution, not a pipe — a piped while runs in a subshell
    # and its fail() calls would not reach the parent's FAILURES counter)
    while IFS= read -r fp; do
        if ! printf '%s' "$fp" | grep -qE '^[A-Za-z0-9+/]{6}$'; then
            fail "$base: unparseable recipient stanza token '$fp'"
        fi
    done < <(file_fps "$file")

    if [ -z "$declared" ]; then
        fail "$base: no well-formed ssh-ed25519 public keys declared"
        return
    fi

    missing="$(comm -23 <(printf '%s\n' "$declared") <(printf '%s\n' "$actual"))"
    extra="$(comm -13 <(printf '%s\n' "$declared") <(printf '%s\n' "$actual"))"

    local i
    if [ -n "$missing" ]; then
        # Map fingerprints back to the declared keys that are absent.
        for p in "${pubs[@]}"; do
            i="$(fp_of_pub "$p")"
            if printf '%s\n' "$missing" | grep -qx "$i"; then
                # Show the key type + start of the b64 field to identify it.
                kprefix="$(printf '%s' "$p" | awk '{print $1" "substr($2,1,12)"…"}')"
                fail "$base: not encrypted to ${kprefix}<fp:${i}> — declared recipient missing from file (stale secret? run scripts/agenix-rekey.sh)"
            fi
        done
    fi
    if [ -n "$extra" ]; then
        while IFS= read -r fp; do
            fail "$base: encrypted to an undeclared recipient (fingerprint ${fp}) — secrets.nix is out of sync with the file"
        done <<< "$extra"
    fi
    if [ -z "$missing$extra" ]; then
        ok "$base: recipients match secrets.nix (${#pubs[@]} key(s))"
    fi
}

# --- mode: host ---------------------------------------------------------------
mode_host() {
    local spec=$1
    local t
    for t in base64 openssl; do
        command -v "$t" >/dev/null 2>&1 || { fail "host mode needs '$t' on PATH"; return 1; }
    done
    [ -f "$spec" ] || { fail "spec file not found: $spec"; return 1; }
    local tmpdir line file keysfile n=0
    tmpdir="$(mktemp -d)" || return 1
    while IFS= read -r line; do
        [ -n "$line" ] || continue
        file="${line%% *}"
        keysfile="$tmpdir/keys.$$.$n"
        # Each key is "ssh-ed25519 <68 b64 chars>" (two words); extract whole
        # keys, one per line, instead of word-splitting the rest of the line.
        printf '%s\n' "${line#* }" | grep -oE 'ssh-ed25519 [A-Za-z0-9+/]{68}' > "$keysfile" || true
        n=$((n + 1))
        check_file "$file" "$keysfile"
    done < "$spec"
    rm -rf "$tmpdir"
    echo "age-audit: audited $n secret file(s) (host mode)"
}

# --- mode: repo -----------------------------------------------------------------
mode_repo() {
    local keystore=${1:-}
    local tmpdir meta json n
    tmpdir="$(mktemp -d)" || return 1
    meta="$tmpdir/meta.json"

    # Note: `--eval --json` cannot convert attrsets whose names contain
    # dots/hyphens ("cannot convert a thunk to JSON"), which secrets.nix has.
    # builtins.toJSON (in-evaluator) handles them fine.
    if ! nix-instantiate --eval -E "builtins.toJSON (import $SECRETS_NIX)" 2> "$tmpdir/meta.err" | jq -r . > "$meta"; then
        fail "secrets.nix does not evaluate: $(head -1 "$tmpdir/meta.err" 2>/dev/null)"
        rm -rf "$tmpdir"
        return 1
    fi
    rm -f "$tmpdir/meta.err"
    ok "secrets.nix evaluates"

    # Declared keys must all be well-formed ssh-ed25519 (no TODO_* placeholders).
    json="$(jq -r '.[] | .publicKeys[]?' "$meta")"
    local bad k
    bad="$(printf '%s\n' "$json" | grep -vE '^ssh-ed25519 [A-Za-z0-9+/]{68}$' | grep -v '^$' || true)"
    if [ -n "$bad" ]; then
        while IFS= read -r k; do
            fail "secrets.nix declares a non ssh-ed25519 value: $k"
        done <<< "$bad"
    else
        ok "all declared public keys are well-formed ssh-ed25519"
    fi

    # Per-secret audit: file exists, recipients == declared set.
    local name file keysfile
    n=0
    while IFS= read -r name; do
        file="$SECRETS_DIR/$name"
        if [ ! -f "$file" ]; then
            fail "secrets.nix lists '$name' but $file does not exist"
            continue
        fi
        keysfile="$tmpdir/keys.$n"
        jq -r --arg n "$name" '.[$n].publicKeys[]?' "$meta" > "$keysfile"
        n=$((n + 1))
        check_file "$file" "$keysfile"
    done < <(jq -r 'keys[]' "$meta")

    # Key store checks (optional): keypair integrity + decryptability.
    if [ -n "$keystore" ]; then
        command -v age >/dev/null 2>&1 || { fail "key-store checks need 'age' on PATH"; rm -rf "$tmpdir"; return; }
        command -v ssh-keygen >/dev/null 2>&1 || { fail "key-store checks need 'ssh-keygen' on PATH"; rm -rf "$tmpdir"; return; }
        [ -d "$keystore/hosts" ] || { fail "key store has no hosts/ directory: $keystore"; rm -rf "$tmpdir"; return; }
        local priv pub raw derived
        for priv in "$keystore"/hosts/*; do
            case "$priv" in *.pub) continue ;; esac
            [ -f "$priv" ] || continue
            if [ ! -f "${priv}.pub" ]; then
                fail "key store: private key without .pub: $priv"
                continue
            fi
            # Compare the first two fields only — both sides may carry a
            # comment that must not affect the pairing check.
            pub="$(awk '{print $1" "$2}' "${priv}.pub")"
            raw="$(ssh-keygen -y -f "$priv" 2>/dev/null)" || {
                fail "key store: unreadable private key: $priv"
                continue
            }
            derived="$(printf '%s\n' "$raw" | awk '{print $1" "$2}')"
            if [ "$derived" = "$pub" ]; then
                ok "key store: $(basename "$priv") pairs with its .pub"
            else
                fail "key store: $(basename "$priv") does NOT pair with its .pub"
            fi
        done

        local f k
        while IFS= read -r f; do
            [ -f "$SECRETS_DIR/$f" ] || continue
            local any=0
            for k in "$keystore"/hosts/*; do
                case "$k" in *.pub) continue ;; esac
                [ -f "$k" ] || continue
                if age -d -i "$k" "$SECRETS_DIR/$f" >/dev/null 2>&1; then
                    any=1
                    break
                fi
            done
            if [ "$any" -eq 1 ]; then
                ok "decryptable: $f"
            else
                fail "no key-store host key decrypts $f (lost key?)"
            fi
        done < <(jq -r 'keys[]' "$meta")
    fi
    rm -rf "$tmpdir"
}

# --- dispatch -------------------------------------------------------------------
case "${1:-}" in
    repo)
        shift
        mode_repo "${1:-}"
        ;;
    host)
        [ $# -ge 2 ] || { echo "usage: $0 host SPEC_FILE" >&2; exit 2; }
        mode_host "$2"
        ;;
    *)
        echo "usage: $0 repo [KEYSTORE_DIR] | host SPEC_FILE" >&2
        exit 2
        ;;
esac

[ "$FAILURES" -eq 0 ] || { echo "age-audit: $FAILURES finding(s)" >&2; exit 1; }
echo "age-audit: clean"
exit 0
