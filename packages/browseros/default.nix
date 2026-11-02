# BrowserOS neo (browseros-ai/BrowserOS) — an agent-driven browser that lets
# AI assistants (Claude Code, Codex, Cursor, opencode, ...) browse the web with
# the user's real logins.
#
# Upstream only publishes prebuilt Electron bundles (no supported source build),
# so wrap the released AppImage with appimageTools.wrapType2. This gives a
# hash-pinned, immutable Nix derivation that cannot self-update.
#
# Update: bump `version` (the AppImage asset version) and the `hash` — by
# hand, nix-update cannot be used: the repo's releases feed mixes several
# release trains (browserclaw/v*, claw-server/v*, ext-browserclaw/v*) and
# nix-update's atom parsing picks whatever entry is newest (it selected
# claw-server/v0.0.89). Also check the newest browserclaw/v release actually
# ships BrowserOS_neo_<version>_x64.AppImage: 0.51.2.4 (2026-10-24) shipped
# Windows installers only, so 0.51.2.3 stayed the Linux pin until 0.52.0
# (2026-10-31) shipped the x64 AppImage again.
#
# Note: the asset version is not always the release tag — on 2026-11-02 the
# 0.52.0 release's assets were deleted and replaced with 0.52.1/0.52.1.1
# builds under the same tag. When bumping, check the release's asset list,
# not just its tag name, and update `releaseTag` separately.
{
  lib,
  appimageTools,
  fetchurl,
  ...
}:

let
  pname = "browseros";
  version = "0.52.1.1";
  # The 0.52.1/0.52.1.1 patch assets were re-uploaded into the 0.52.0 release
  # (its original v0.52.0 assets were deleted 2026-11-02), so the asset
  # version no longer matches the release tag.
  releaseTag = "browserclaw/v0.52.0";

  src = fetchurl {
    # Since 0.51.1.2 the neo releases tag as "browserclaw/v<version>" and the
    # AppImage is named BrowserOS_neo_v<version>_x64.AppImage.
    url = "https://github.com/browseros-ai/BrowserOS/releases/download/${releaseTag}/BrowserOS_neo_v${version}_x64.AppImage";
    # x86_64 build only; upstream also ships BrowserOS_neo_v${version}_amd64.deb.
    # Hash from the release's published asset digest (SHA256SUMS-0.52.1.1.txt).
    hash = "sha256-xiwFDB/Wdih7EbIDKUqwXI7mrYrvojaarb2gs34aE3k=";
  };

  # Extract once so extraInstallCommands can install the desktop entry and icon.
  appimageContents = appimageTools.extract {
    inherit pname version src;
  };
in
appimageTools.wrapType2 {
  inherit pname version src;

  extraInstallCommands = ''
    # 0.51.1.2 rebranded the bundle's entry to browserclaw (the release tag
    # is browserclaw/v... and the desktop file is browserclaw.desktop).
    install -Dm444 ${appimageContents}/browserclaw.desktop \
      $out/share/applications/browserclaw.desktop

    install -Dm444 ${appimageContents}/browserclaw.png \
      $out/share/icons/hicolor/512x512/apps/browserclaw.png

    substituteInPlace $out/share/applications/browserclaw.desktop \
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
