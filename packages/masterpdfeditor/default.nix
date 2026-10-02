# Master PDF Editor (proprietary) packaged with a fixed vendor version and a
# wrapper that forces the X11/XCB Qt backend (fixes popup-rendering issues).
#
# Previously this overrideAttrs block was duplicated in roles/system.nix (for
# the system profile) and users/nicky/nicky-hm.nix (for nicky's home profile),
# and the two copies had already diverged (license path, Qt wrapper). This is
# the single canonical version (IVP: same change driver {D-PKG, D-APP} kept
# together).
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

  # Disable fixup (custom binary location) and the automatic Qt wrapper (we
  # control the Qt env below).
  dontFixup = true;
  dontWrapQtApps = true;
  nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [ makeWrapper ];

  # I don't know why the installPhase must be overridden, but without it the
  # script does not find license_en.txt (which it shouldn't even try to use...)
  # and fails.
  installPhase = ''
    runHook preInstall

    p=$out/opt/masterpdfeditor
    mkdir -p $out/bin

    substituteInPlace masterpdfeditor5.desktop \
      --replace 'Exec=/opt/master-pdf-editor-5' "Exec=$out/bin" \
      --replace 'Path=/opt/master-pdf-editor-5' "Path=$out/bin" \
      --replace 'Icon=/opt/master-pdf-editor-5' "Icon=$out/share/pixmaps"

    install -Dm644 -t $out/share/pixmaps      masterpdfeditor5.png
    echo -e '\nStartupWMClass=net.code-industry.masterpdfeditor5' >> masterpdfeditor5.desktop
    install -Dm644 -t $out/share/applications masterpdfeditor5.desktop
    install -Dm755 -t $p                      masterpdfeditor5
    install -Dm644 license.txt $out/share/licenses/$pname/LICENSE
    ln -s $p/masterpdfeditor5 $out/bin/masterpdfeditor5
    cp -v -r stamps templates lang fonts $p

    runHook postInstall

    # Wrapper that sets Qt env vars to fix popup rendering:
    #  QT_QPA_PLATFORM=xcb: force the X11/XCB backend
    #  QT_XCB_GL_INTEGRATION=none: disable OpenGL integration
    #  LD_LIBRARY_PATH: add the required X11/OpenGL libraries
    mv $out/bin/masterpdfeditor5 $out/bin/.masterpdfeditor5-unwrapped
    makeWrapper $out/bin/.masterpdfeditor5-unwrapped $out/bin/masterpdfeditor5 \
      --set QT_QPA_PLATFORM xcb \
      --set QT_XCB_GL_INTEGRATION none \
      --prefix LD_LIBRARY_PATH : ${lib.makeLibraryPath [ libx11 libxrandr libGL ]}
  '';
})
