# The Strata desktop app (Tauri 2), installed as upstream's Linux AppImage.
#
# Upstream publishes the app only as prebuilt installers; the Linux artifact is
# a Tauri AppImage that carries its own Node sidecar, its own Strata Control
# (pinned CPython + hash-locked wheels) and an engine package. Consequences,
# all from 0.2.3.1's `apps/host/server/`:
#
# - It does NOT reuse the systemd `strata.service` *process* or its port: the
#   app starts its own server through its bundled Control (control-runtime.mjs:
#   owner runtime, "leases that stop a second owner"; the start takes
#   `--die-with-pid` so the server ends with the app). That only matters when a
#   *local* model is loaded in the app. As a front end it is just a client: a
#   saved API connection (model-providers.mjs, `kind: "custom"`) with any base
#   URL and the openai-chat, openai-responses or anthropic protocol - which
#   covers a running strata.service (http://127.0.0.1:8080/v1) and Unsloth
#   Studio (http://127.0.0.1:8888/v1) with /models autodiscovery. In that mode
#   nothing must be stopped; `wrapper` only frees the card on request.
# - It does NOT reuse the Nix-built engine binary. bundled-engine.mjs looks for
#   an engine *component package* under <components>/engine/ (checked against
#   engine-component.json); packages/strata writes ~/.local/share/strata/engine
#   with a BUILD.json instead, which is not that shape. First start copies the
#   bundled 0.1.48 engine into ~/.local/share/strata/components (~1 GB); an
#   installed component of the same or a newer version is never touched.
# - It DOES share the models. Models folder, run configs, MTP layer and the
#   inventory are one set for the app and the Terminal ("Desktop and Terminal
#   share the same model inventory, profiles, runtime and agent sessions"), so
#   ~/.local/share/Strata-data is used by both and nothing is re-downloaded.
#
# The AppImage is symlinked from ~/.local/opt (see home.nix), so upstream's
# Settings > Update cannot rewrite a read-only store path: update by bumping
# both pins here and packages/strata/default.nix's tag together.
{
  runCommand,
  fetchurl,
  writeShellScriptBin,
}:

let
  # Release v0.2.3.1 carries artifacts named 0.2.3: 0.2.3.1 changed only the
  # Terminal's Control (0.1.48.1); the app and the engine packages are the
  # 0.2.3 files. NVIDIA CUDA 13 build: the lane engine.nix builds for
  # (engine/ = CUDA 13, engine-cuda12/ is the experimental one), and the build
  # upstream's packaging matrix ran. Needs driver >= 580.
  tag = "v0.2.3.1";
  version = "0.2.3";

  src = fetchurl {
    name = "Strata-${version}-linux-nvidia-cuda13.AppImage";
    url = "https://github.com/Niko1221/Strata/releases/download/${tag}/Strata-${version}-linux-nvidia-cuda13.AppImage";
    hash = "sha256-RxKvw/mEDuL8zpDvaVR4/dPbHX0CFN6Q87D99Iw1Hm0=";
  };

  # 128x128@2x = what a 256x256 hicolor entry wants. fetchurl refuses a file
  # name with an "@" in it, hence the explicit name.
  icon = fetchurl {
    name = "strata-desktop.png";
    url = "https://raw.githubusercontent.com/Niko1221/Strata/${tag}/apps/desktop/src-tauri/icons/128x128@2x.png";
    hash = "sha256-ycqt39GkVVvX6RWam2vcgGRTbYcXKUJVBB4RXq2r2Cc=";
  };

  # fetchurl's file is mode 444 and a home.file symlink adds no mode of its
  # own, so hand out an executable copy in the store instead.
  appImage = runCommand "Strata-${version}.AppImage" { } "install -m755 ${src} $out";
in
{
  inherit appImage icon;

  # The launcher the menu entry points at. By default it starts the app and
  # changes nothing: the app may well be pointed at a running server or another
  # API (see the header), and stopping that would break the very connection it
  # uses. Only when the person intends to load a *local* model in the app - its
  # own engine then needs the whole 12 GB card, and one owner holds it at a
  # time - the module sets STRATA_APP_STOP_SERVER=1 and the launcher frees the
  # GPU first, the way the `strata` wrapper does. `laya-mcp` exists on some
  # hosts only; systemctl's failure there is expected and ignored.
  wrapper = writeShellScriptBin "strata-app" ''
    if [ "''${STRATA_APP_STOP_SERVER:-0}" = 1 ]; then
      for unit in strata unsloth-studio laya-mcp; do
        if systemctl --user is-active --quiet "$unit" 2>/dev/null; then
          echo "Strata app: stopping $unit (frees VRAM/RAM for a local model)..." >&2
          systemctl --user stop "$unit" || true
        fi
      done
    fi
    "${appImage}" "$@"
    status=$?
    if [ "''${STRATA_APP_STOP_SERVER:-0}" = 1 ]; then
      echo "Strata app closed. Restart the server with: systemctl --user start strata.service" >&2
    fi
    exit $status
  '';
}
