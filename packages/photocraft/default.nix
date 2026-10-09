# PhotoCraft (storytold/photocraft, https://getartcraft.com/apps/photocraft) —
# a native, clean-room Photoshop reimplementation in pure Rust: layers, masks,
# adjustment layers, type, vectors and real PSD files.
#
# Not in nixpkgs, and upstream publishes only prebuilt Linux bundles (AppImage,
# .deb, .rpm, tarball, Flatpak) — no source build we want to pay for here (24
# crates + wgpu). Wrap the released AppImage with appimageTools.wrapType2: it is
# extracted and run inside an FHS env carrying the libraries a desktop appimage
# expects (Vulkan, Wayland, X11/XCB, fontconfig, ...), so the result is a
# normal, hash-pinned, immutable derivation that cannot self-update and never
# writes its launcher into ~/.local/share.
#
# Update: bump `version` (and the hash) — `nix-update --flake photocraft` does
# both. The AppImage also ships `usr/bin/photocraft-cli` (the headless agent
# CLI); it is not exposed here — the desktop app is the goal, and the CLI would
# need its own FHS-run wrapper. See git history if that is wanted later.
{
  lib,
  appimageTools,
  fetchurl,
  ...
}:

let
  pname = "photocraft";
  version = "0.3.0";

  src = fetchurl {
    url = "https://github.com/storytold/photocraft/releases/download/v${version}/photocraft-${version}-linux-x86_64.AppImage";
    # x86_64 build only; upstream also ships -linux-aarch64.AppImage.
    hash = "sha256-KeMBH0mlLqJcj+QEJYpsX62wIJTbtAqITWnmuoCOYTY=";
  };

  # Extract the AppImage a second time (wrapType2's internal extraction is the
  # same derivation) so extraInstallCommands below can install the desktop
  # entry, hicolor icons, MIME types and AppStream metadata the bundle carries.
  # Without it the wrapper exposes only bin/photocraft and the menu shows a
  # generic icon.
  appimageContents = appimageTools.extract {
    inherit pname version src;
  };
in
appimageTools.wrapType2 {
  inherit pname version src;

  # appimageTools.wrapType2 exposes bin/photocraft (buildFHSEnv uses pname as
  # the executable name) but drops the entry, icons, MIME and metainfo inside
  # the bundle. Install them here. Upstream's desktop file is already named
  # `ai.storyteller.photocraft.desktop` and Execs `photocraft`, which matches
  # the wrapped binary, so no substitution is needed.
  extraInstallCommands = ''
    install -Dm444 ${appimageContents}/usr/share/applications/ai.storyteller.photocraft.desktop \
      $out/share/applications/ai.storyteller.photocraft.desktop

    for icon in ${appimageContents}/usr/share/icons/hicolor/*/apps/ai.storyteller.photocraft.*; do
      install -Dm444 "$icon" "$out/share/icons/hicolor/$(basename "$(dirname "$(dirname "$icon")")")/apps/$(basename "$icon")"
    done

    install -Dm444 ${appimageContents}/usr/share/mime/packages/ai.storyteller.photocraft.xml \
      $out/share/mime/packages/ai.storyteller.photocraft.xml

    install -Dm444 ${appimageContents}/usr/share/metainfo/ai.storyteller.photocraft.metainfo.xml \
      $out/share/metainfo/ai.storyteller.photocraft.metainfo.xml
  '';

  meta = with lib; {
    description = "Image editor: layers, masks, adjustment layers, type, vectors and real PSD files (clean-room Photoshop reimplementation)";
    homepage = "https://getartcraft.com/apps/photocraft";
    license = with licenses; [
      mit
      asl20
    ];
    mainProgram = "photocraft";
    # The pinned URL is the x86_64 AppImage specifically (upstream also ships
    # an aarch64 one); do not advertise aarch64-linux as available.
    platforms = [ "x86_64-linux" ];
    sourceProvenance = with sourceTypes; [ binaryNativeCode ];
  };
}
