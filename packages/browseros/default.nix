# BrowserOS neo (browseros-ai/BrowserOS) — an agent-driven browser that lets
# AI assistants (Claude Code, Codex, Cursor, opencode, ...) browse the web with
# the user's real logins.
#
# Upstream only publishes prebuilt Electron bundles (no supported source build),
# so wrap the released AppImage with appimageTools.wrapType2. This gives a
# hash-pinned, immutable Nix derivation that cannot self-update.
#
# Update: bump `version` and the AppImage `hash`.
{
  lib,
  appimageTools,
  fetchurl,
  ...
}:

let
  pname = "browseros";
  version = "0.51.0";

  src = fetchurl {
    url = "https://github.com/browseros-ai/BrowserOS/releases/download/v${version}/BrowserOS_v${version}_x64.AppImage";
    # x86_64 build only; upstream also ships BrowserOS_v${version}_amd64.deb.
    hash = "sha256-tYbfcgg8BG4uotHMG2RjMl7Uywwxl11I4JzBQhXj578=";
  };

  # Extract once so extraInstallCommands can install the desktop entry and icon.
  appimageContents = appimageTools.extract {
    inherit pname version src;
  };
in
appimageTools.wrapType2 {
  inherit pname version src;

  extraInstallCommands = ''
    install -Dm444 ${appimageContents}/browseros.desktop \
      $out/share/applications/browseros.desktop

    install -Dm444 ${appimageContents}/browseros.png \
      $out/share/icons/hicolor/512x512/apps/browseros.png

    substituteInPlace $out/share/applications/browseros.desktop \
      --replace-fail 'Exec=AppRun %U' 'Exec=${pname} %U'
  '';

  meta = with lib; {
    description = "Agent-driven browser that lets AI assistants use the web with your logins";
    homepage = "https://browseros.com";
    license = licenses.agpl3Only;
    mainProgram = pname;
    platforms = platforms.linux;
    sourceProvenance = with sourceTypes; [ binaryNativeCode ];
  };
}
