# Strata desktop app (Tauri 2) — upstream's Linux AppImage.
#
# Since 0.2.5 the AppImage ships no engine: the engine component is a separate
# download (strata-engine-0.1.xx-*) installed via the app's Settings > Updates
# or `strata update`. The app runs its own Control (bundled Python + hash-locked
# wheels) and starts its own server via `--die-with-pid` (the server ends with
# the app). That only matters when loading a *local* model in the app. As a
# front end it is just a client: a saved API connection (model-providers.mjs,
# `kind: "custom"`) with any base URL and the openai-chat, openai-responses or
# anthropic protocol — covering this package's server (http://127.0.0.1:8080/v1)
# and Unsloth Studio (http://127.0.0.1:8888/v1) with /models autodiscovery.
#
# The desktop app and the Terminal are always version-locked: when this package
# is bumped, the AppImage is bumped in the same change (enforced by home.nix).
# The AppImage cannot update itself from the Nix store (write-protected), so
# the desktop app finds the store-built engine component already installed
# (the wrapper installs it into $STRATA_HOME/components/ before any invocation).
{
  lib,
  runCommand,
  fetchurl,
  writeShellScriptBin,
}:

let
  # Version-locked with packages/strata/default.nix: both use the same tag.
  tag = "v0.2.18";
  version = "0.2.18";

  src = fetchurl {
    name = "Strata-${version}-linux-x86_64.AppImage";
    url = "https://github.com/Niko1221/Strata/releases/download/${tag}/Strata-${version}-linux-x86_64.AppImage";
    hash = "sha256:5c43c53025bfc0727aa31aac9880727cd6e2ad2b268d02527e70b1085a0c6553";
  };

  icon = fetchurl {
    name = "strata-desktop.png";
    url = "https://raw.githubusercontent.com/Niko1221/Strata/${tag}/app/desktop/src-tauri/icons/128x128@2x.png";
    hash = "sha256:c9caaddfd1a4555bd7e9159a9b6bdc8064536d8717294255041e115eadabd827";
  };

  # fetchurl's file is mode 444 and a home.file symlink adds no mode of its
  # own, so hand out an executable copy in the store instead.
  appImage = runCommand "Strata-${version}.AppImage" { } "install -m755 ${src} $out";
in
{
  inherit appImage icon;

  # The launcher the menu entry points at.
  wrapper = writeShellScriptBin "strata-app" ''
    if [ "''${STRATA_APP_STOP_SERVER:-0}" = 1 ]; then
      for unit in strata unsloth-studio; do
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

  meta = with lib; {
    description = "Strata desktop app (Tauri 2) — version-locked to the Terminal";
    homepage = "https://github.com/Niko1221/Strata";
    license = licenses.mit;
    platforms = platforms.linux;
    mainProgram = "strata-app";
  };
  passthru = { inherit version; };
}
