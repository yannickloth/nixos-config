#!/usr/bin/env bash
# One-time UID migration for the kids' accounts (sven -> 1002, aaron -> 1003).
#
# Why: users/<n>.nix now pins explicit uids (so the Tor kid-block can be a
# declarative nftables rule), but NixOS' update-users-groups.pl NEVER changes an
# existing user's uid — it warns and keeps the old one. So on an
# already-installed host you must move the account and the files it owns once.
#
#   sudo ./scripts/migrate-uid.sh            # dry-run: show uids + files
#   sudo ./scripts/migrate-uid.sh --apply    # actually migrate
#
# It runs `usermod -u <new> <user>` (updates /etc/passwd) and then chowns every
# file owned by the OLD uid to that user. After it, `nixos-rebuild switch`
# keeps the new uid (declared == existing, so the perl leaves it alone).
#
# Paths that are NOT chowned (and why):
#   /sync/sven, /sync/aaron  - owned by the syncthing daemon; the kids reach
#                              them via name-based ACLs, which resolve the
#                              current uid, so no chown is needed.
#   /filedrop                - owned by root:filedrop, group-based.
#   /.snapshots/**, /nix/**  - read-only snapshots / store.
#
# If you would rather NOT migrate, the alternative is to set the config uids to
# the accounts' current values (`getent passwd sven aaron`) — no chown needed.

set -euo pipefail

# user:target_uid  (must match users/<user>/<user>.nix)
MAP=(
  "sven:1002"
  "aaron:1003"
)

APPLY=0
[[ "${1:-}" == "--apply" ]] && APPLY=1

if [[ "$EUID" -ne 0 ]]; then
  echo "error: run as root (this changes /etc/passwd and file ownership)." >&2
  exit 1
fi
command -v usermod >/dev/null 2>&1 || {
  echo "error: 'usermod' not found (nix shell nixpkgs#shadow)." >&2
  exit 1
}

find_owned() { # <old_uid>
  find / -xdev -uid "$1" \
    -not -path '/nix/*' -not -path '/proc/*' -not -path '/sys/*' \
    -not -path '/dev/*' -not -path '/.snapshots/*' -print 2>/dev/null || true
}

for entry in "${MAP[@]}"; do
  user="${entry%%:*}"
  target="${entry##*:}"

  if ! getent passwd "$user" >/dev/null; then
    echo "$user: no such account on this host; skip"
    continue
  fi

  old="$(getent passwd "$user" | cut -d: -f3)"
  if [[ "$old" == "$target" ]]; then
    echo "$user: already uid $target; nothing to do"
    continue
  fi

  echo "== $user: uid $old -> $target =="
  mapfile -t files < <(find_owned "$old")
  echo "   files owned by uid $old: ${#files[@]}"
  printf '   e.g. %s\n' "${files[@]:0:5}"

  if (( ! APPLY )); then
    continue
  fi

  usermod -u "$target" "$user"
  # Re-scan for the old uid (usermod does not chown), then chown each path to
  # the user (owner only; group membership is unchanged).
  while IFS= read -r -d '' p; do
    chown -h "$user" "$p"
  done < <(find / -xdev -uid "$old" \
    -not -path '/nix/*' -not -path '/proc/*' -not -path '/sys/*' \
    -not -path '/dev/*' -not -path '/.snapshots/*' -print0 2>/dev/null || true)

  remaining="$(find_owned "$old" | wc -l)"
  echo "   done; files still owned by uid $old: $remaining (should be 0)"
done

if (( APPLY )); then
  echo
  echo "Now run: sudo nixos-rebuild switch   (declared uid now matches)."
else
  echo
  echo "Dry-run. Re-run with --apply to migrate."
fi
