# Master PDF Editor (proprietary) packaged with a fixed vendor version and a
# wrapper that forces the X11/XCB Qt backend (fixes popup-rendering issues).
#
# Previously this overrideAttrs block was duplicated in roles/system.nix (for
# the system profile) and users/nicky/nicky-hm.nix (for nicky's home profile),
# and the two copies had already diverged (license path, Qt wrapper). This is
# the single canonical version (IVP: same change driver {D-PKG, D-APP} kept
# together).
#
# Layout note: the base derivation's `preFixup` runs
# `patchelf $out/share/masterpdfeditor/masterpdfeditor5 --add-needed libsmime3.so`
# and autoPatchelfHook (fixupPhase) patches the prebuilt ELF, so this override
# must install the binary at exactly that path — do NOT move it to $out/opt,
# and do NOT set `dontFixup` (that would leave the binary with the upstream
# interpreter/RPATH).
{ lib
, masterpdfeditor
, makeWrapper
, fetchurl
, libx11
, libxrandr
, libGL
}:

masterpdfeditor.overrideAttrs (old: rec {
  pname = "masterpdfeditor";
  version = "5.8.70";
  src = fetchurl {
    url = "https://code-industry.net/public/master-pdf-editor-${version}-qt5.x86_64.tar.gz";
    sha256 = "sha256-mheHvHU7Z1jUxFWEEfXv2kVO51t/edTK3xV82iteUXM=";
  };

  # Keep fixup enabled (autoPatchelfHook lives there and the prebuilt binary
  # needs its interpreter/RPATH rewritten). Only the automatic Qt wrapper is
  # disabled: the Qt env is set explicitly in postFixup below.
  dontWrapQtApps = true;
  nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [ makeWrapper ];

  # This tarball is the plain (non `-qt_include`) build and its shipped
  # desktop file points at /opt, so the install phase is still custom — but it
  # installs into share/masterpdfeditor, where the base's preFixup,
  # autoPatchelfHook and mainProgram expect the binary.
  installPhase = ''
    runHook preInstall

    p=$out/share/masterpdfeditor
    mkdir -p $out/bin "$p"

    substituteInPlace masterpdfeditor5.desktop \
      --replace 'Exec=/opt/master-pdf-editor-5' "Exec=$out/bin" \
      --replace 'Path=/opt/master-pdf-editor-5' "Path=$p" \
      --replace 'Icon=/opt/master-pdf-editor-5' "Icon=masterpdfeditor5"

    install -Dm644 -t $out/share/pixmaps      masterpdfeditor5.png
    echo -e '\nStartupWMClass=net.code-industry.masterpdfeditor5' >> masterpdfeditor5.desktop
    install -Dm644 -t $out/share/applications masterpdfeditor5.desktop
    install -Dm755 -t "$p"                    masterpdfeditor5
    install -Dm644 license.txt $out/share/licenses/$pname/LICENSE
    cp -r stamps templates lang fonts "$p"
    ln -s "$p/masterpdfeditor5" $out/bin/masterpdfeditor5

    runHook postInstall
  '';

  # Wrapper that sets Qt env vars to fix popup rendering:
  #  QT_QPA_PLATFORM=xcb: force the X11/XCB backend
  #  QT_XCB_GL_INTEGRATION=none: disable OpenGL integration
  #  LD_LIBRARY_PATH: add the required X11/OpenGL libraries
  # Runs after fixup so it wraps the already-patched binary.
  postFixup = ''
    mv $out/bin/masterpdfeditor5 $out/bin/.masterpdfeditor5-unwrapped
    makeWrapper $out/bin/.masterpdfeditor5-unwrapped $out/bin/masterpdfeditor5 \
      --set QT_QPA_PLATFORM xcb \
      --set QT_XCB_GL_INTEGRATION none \
      --prefix LD_LIBRARY_PATH : ${lib.makeLibraryPath [ libx11 libxrandr libGL ]}
  '';
})
