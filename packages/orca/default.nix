# Orca (stablyai/orca, https://onorca.dev) — the agent development
# environment (ADE): run many coding-agent CLIs (opencode, Claude Code, Codex,
# Pi, DeepSeek Harness, ...) side by side, each in its own git worktree.
#
# Not in nixpkgs, and upstream only publishes a prebuilt Electron bundle (no
# supported source build; the pipeline is a large pnpm workspace + native
# modules + electron-builder). Instead of the imperative "download the
# AppImage into ~ and let it self-update" pattern used for Unsloth Desktop,
# wrap the released AppImage with appimageTools.wrapType2: it is extracted and
# run inside an FHS env carrying every library the bundle expects (the same
# list upstream's Ubuntu guide apt-installs, provided here by
# defaultFhsEnvArgs). The result is a normal, hash-pinned, immutable Nix
# derivation that never writes to the store and cannot self-update.
#
# Update: bump `version` (and the hash) — `nix-update --flake orca` does both.
# The AppImage binary is invoked directly, so the `bin/orca-ide` name matches
# upstream's Linux CLI (kept distinct from nixpkgs' `orca`, the GNOME screen
# reader). `orca-ide serve ...` runs the headless runtime server.
{
  lib,
  appimageTools,
  fetchurl,
  xvfb,
  ...
}:

let
  pname = "orca-ide";
  version = "1.4.221";

  src = fetchurl {
    url = "https://github.com/stablyai/orca/releases/download/v${version}/orca-linux.AppImage";
    # x86_64 build only; upstream also ships orca-linux-arm64.AppImage.
    hash = "sha256-e/F7NhnCpPI0axiUxlLieQuJJ35QGnjOiREkml4S8PY=";
  };

  # Extract the AppImage a second time (wrapType2's internal extraction is the
  # same derivation) so extraInstallCommands below can install the desktop
  # entry and hicolor icons the bundle carries. Without it the wrapper exposes
  # only bin/orca-ide, the menu shows a generic icon, and home.nix has to
  # hand-roll a desktop entry.
  appimageContents = appimageTools.extract {
    inherit pname version src;
  };
in
appimageTools.wrapType2 {
  inherit pname version src;

  # The AppImage keeps the Electron libraries it links against; add only what
  # it does NOT bundle. Xvfb lets `orca-ide serve` come up on a headless host
  # (Orca starts its own :99 display when DISPLAY is unset).
  extraPkgs = pkgs: [ xvfb ];

  # appimageTools.wrapType2 only exposes bin/orca-ide, dropping the entry and
  # icons inside the bundle. Install them here. Upstream's file is already
  # named orca-ide.desktop — deliberately NOT orca.desktop, which is the GNOME
  # Orca screen reader's id and, because /usr/share outranks the profile in
  # XDG_DATA_DIRS, would shadow this entry in the menu.
  extraInstallCommands = ''
    install -Dm444 ${appimageContents}/orca-ide.desktop \
      $out/share/applications/orca-ide.desktop

    for size in 16 24 32 48 64 128 256 512; do
      install -Dm444 ${appimageContents}/usr/share/icons/hicolor/''${size}x''${size}/apps/orca-ide.png \
        $out/share/icons/hicolor/''${size}x''${size}/apps/orca-ide.png
    done

    substituteInPlace $out/share/applications/orca-ide.desktop \
      --replace-fail 'Exec=AppRun' 'Exec=${pname}'
  '';

  meta = with lib; {
    description = "Agent development environment (ADE) for running many coding agents in parallel git worktrees";
    homepage = "https://onorca.dev";
    license = licenses.mit;
    mainProgram = "orca-ide";
    platforms = platforms.linux;
    sourceProvenance = with sourceTypes; [ binaryNativeCode ];
  };
}
