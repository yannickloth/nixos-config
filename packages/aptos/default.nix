# Microsoft Aptos font family.
#
# Upstream publishes the family as a free (but unfree/redistribution-restricted)
# ZIP on the Microsoft Download Center. The package installs only the TrueType
# files plus the EULA; add it to `fonts.packages` to make Aptos available
# system-wide.
{
  lib,
  stdenvNoCC,
  fetchzip,
}:

stdenvNoCC.mkDerivation rec {
  pname = "aptos";
  version = "4.40";

  src = fetchzip {
    url = "https://download.microsoft.com/download/8/6/0/860a94fa-7feb-44ef-ac79-c072d9113d69/Microsoft%20Aptos%20Fonts.zip";
    hash = "sha256-jkYOP5upe+zMnuQtDLCAcaG1ocbx1iHm1ygW9pqGTig=";
    stripRoot = false;
  };

  installPhase = ''
    mkdir -p $out/share/fonts/truetype
    cp *.ttf $out/share/fonts/truetype/

    install -Dm644 "Microsoft Aptos Fonts EULA.rtf" \
      "$out/share/licenses/aptos/Microsoft Aptos Fonts EULA.rtf"
  '';

  meta = with lib; {
    description = "Microsoft Aptos font family (sans, serif, mono, display, narrow)";
    homepage = "https://learn.microsoft.com/en-us/typography/font-list/aptos";
    license = licenses.unfree;
    platforms = platforms.all;
    sourceProvenance = with sourceTypes; [ binaryNativeCode ];
  };
}
