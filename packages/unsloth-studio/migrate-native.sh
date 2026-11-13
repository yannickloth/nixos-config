#!/bin/sh
# Migrate the native Unsloth Studio install's data into the container volume.
#
# backend = "container" starts from an empty Studio DB: provider connections,
# their API keys, chats, the Decision API panel (systemone_*) and every other
# app_settings row live in ~/.unsloth/studio/studio.db and would be lost. All of
# that data is exactly what the image mounts at $UNSLOTH_STUDIO_HOME
# (/opt/unsloth-studio), so copying the native home into the volume keeps it.
#
# Run as the owning user with the native unit stopped:
#
#   systemctl --user stop unsloth-studio
#   ./migrate-native.sh            # refuses if the volume already has a DB
#
# The image's start script relinks code (venv, src, node, engines) from
# /opt/unsloth-studio-app into the home and moves any real directory that is in
# the way to .unsloth-studio-legacy/. The excludes below only save time and
# volume space; leaving them in would not break the start.
#
# Not copied on purpose: engines (llama.cpp, whisper.cpp, audio.cpp,
# stable-diffusion.cpp) live under ~/.unsloth, not in the Studio home, and the
# image bakes its own. Models are not in the DB either: ~/.cache/huggingface is
# bind-mounted into the container, so they survive as they are.
set -eu

volume=unsloth-studio
src=$HOME/.unsloth/studio
podman=$(command -v podman || echo /usr/bin/podman)
[ -x "$podman" ] || { echo "podman not found" >&2; exit 1; }
[ -f "$src/studio.db" ] || { echo "no native Studio DB at $src/studio.db" >&2; exit 1; }

graphroot=$("$podman" info --format '{{.Store.GraphRoot}}' 2>/dev/null || true)
echo "podman graphroot: ${graphroot:-unknown}"
case "$graphroot" in
  /data/*) ;;
  *) echo "WARNING: the volume will land on $graphroot, not /data. Write" \
            "~/.config/containers/storage.conf first (see packages/unsloth-studio/container.nix)." >&2 ;;
esac

"$podman" volume exists "$volume" 2>/dev/null || "$podman" volume create "$volume" >/dev/null
mp=$("$podman" volume inspect -f '{{.Mountpoint}}' "$volume")
echo "volume $volume -> $mp"

if [ -e "$mp/studio.db" ]; then
  echo "refusing: $mp already holds a Studio DB (the container ran)." >&2
  echo "To replace it anyway: podman rm -f $volume; podman volume rm $volume; rerun." >&2
  exit 1
fi

# The native unit must be stopped: an open WAL copied mid-write is a torn DB.
if pgrep -f "unsloth studio" >/dev/null 2>&1; then
  echo "refusing: a Studio process is running. systemctl --user stop unsloth-studio first." >&2
  exit 1
fi

# -a keeps the auth/ file modes (0400 secrets, 0600 DB); -H preserves hardlinks.
rsync -aH --info=progress2 \
  --exclude 'unsloth_studio' \
  --exclude 'src' \
  --exclude 'node' \
  --exclude 'node_modules' \
  --exclude 'bin' \
  --exclude 'llama.cpp' \
  --exclude 'whisper.cpp' \
  --exclude 'audio.cpp' \
  --exclude 'stable-diffusion.cpp' \
  --exclude 'cache/uv' \
  --exclude '.venv_t5_*' \
  --exclude '.unsloth-studio-legacy' \
  "$src/" "$mp/"

printf '%s\n' \
  "migrated into the volume: providers, credentials, chats, app_settings (incl. systemone_*)." \
  "Next: start the container (systemctl --user start unsloth-studio). The old Studio" \
  "password keeps working; UNSLOTH_STUDIO_PASSWORD only applies to a fresh volume." \
  "Two things still break across the container boundary:" \
  "  - a provider whose base_url is http://localhost:... must become http://host.containers.internal:..." \
  "  - keyless localhost access does not survive a published port: create API keys."
