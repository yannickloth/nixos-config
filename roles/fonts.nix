# configuration for fonts

{ config, lib, pkgs, ... }:

with lib;

{
  config = {
    fonts = {
      # The NixOS default set pulls in noto-fonts-cjk-sans/serif (and
      # unifont) for full Unicode coverage. This installation is used in
      # FR/DE/LU/NL/EN/PT only, so those faces are dead weight: keep the
      # default Latin/Greek/Cyrillic families explicitly below and opt out
      # of the CJK-heavy defaults.
      enableDefaultPackages = false;
      fontconfig = {
        enable = mkForce true;
        defaultFonts = {
          # Family names only: fontconfig matches these against the family,
          # not the file/size ("Iosevka 11" is not a family name).
          monospace = ["Iosevka"];
          sansSerif = ["Inter"];
          serif = ["Roboto Slab"];
        };
      };
      fontDir = {
        enable = true;
      };
      packages = with pkgs; [
        adwaita-icon-theme # for apps like simple-scan
        (pkgs.callPackage ../packages/aptos { }) # Microsoft Aptos (Office default) family
        caladea
        carlito
        charis # Recommended by Matthew Butterick
        stix-two # STIX Two, a Unicode font covering scientific and mathematical notation
        cooper-hewitt # Recommended by Matthew Butterick
        corefonts
        courier-prime
        dejavu_fonts
        dina-font
        encode-sans
        garamond-libre
        gelasio
        gentium #
        gentium-book-basic #
        gyre-fonts
        hasklig
        # IBM Plex Latin families only. The full package also ships Arabic,
        # Devanagari, Hebrew, Thai and CJK families, which this user cannot
        # use; selecting the Latin families keeps the typeface here without
        # dragging in the dead scripts.
        (ibm-plex.override {
          families = [ "serif" "sans" "sans-condensed" "mono" "math" ];
        }) # Recommended by Matthew Butterick
        intel-one-mono # Intel One Mono, an expressive monospaced font family that’s built with clarity, legibility, and the needs of developers in mind.
        inter
        iosevka
        iosevka-comfy.comfy
        # Ioskeley Mono (compact geometric programming typeface built with
        # Iosevka, inspired by Berkeley Mono). Six variants, each a distinct
        # fontconfig family: the hinted default, plus the no-ligature (NL),
        # Nerd Font (NF) and terminal-metric (term) cuts with their
        # permutations.
        #
        # NOT the *-unhinted builds: nixpkgs' normal-unhinted ships the SAME
        # file names (IoskeleyMono-Black.ttf) AND the same family name
        # ("Ioskeley Mono") as normal, so buildEnv cannot merge the two and
        # fontconfig could not tell them apart anyway. Adding one alongside its
        # hinted sibling fails the whole system build with "two given paths
        # contain a conflicting subpath". Pick one hinting per family.
        ioskeley-mono.normal
        ioskeley-mono.normal-NL
        ioskeley-mono.normal-NF
        ioskeley-mono.normal-term
        ioskeley-mono.normal-NL-NF
        ioskeley-mono.normal-term-NF
        liberation_ttf
        material-design-icons
        merriweather
        montserrat
        # Quality typography — serif (with italics), display, script, classic.
        # Each chosen for italic support and publishing-grade rendering.
        alegreya # elegant serif with full italic range; readability for long-form prose
        crimson-pro # modern serif, extensive weight range + italics; workhorse for long-form publishing
        libre-bodoni # high-contrast modern face; headlines, editorial display
        libre-caslon # Text (Reg/It/Bold) + Display; the classic typesetter's face
        league-gothic # condensed display with italic; pull quotes, captions, section headers
        league-script-number-one # handwriting-style script for signatures, quotes, annotations
        dancing-script # flowing, legible script for emphasis in documents
        cardo # classical academic serif; small caps, antiqua for footnotes and citations
        nerd-fonts.fira-code
        nerd-fonts.jetbrains-mono
        nerd-fonts.ubuntu
        open-sans
        overpass # the open source typeface used by the Red Hat brand identity.
        raleway
        redhat-official-fonts
        # roboto # no need for this, the inter font just looks better. https://mattwestcott.org/blog/an-ode-to-the-inter-typeface
        roboto-slab
        sn-pro # SN Pro Font Family (https://supernotes.app/open-source/sn-pro/). SN Pro is a friendly sans serif typeface optimized for use with Markdown.
        source-code-pro
        source-sans # Source Sans 3, the current upstream name; WordCraft hard-codes "Source Sans 3" / "SourceSans".
        source-sans-pro # Legacy Source Sans Pro name, still referenced by some documents.
        terminus_font
        #twemoji-color-font
        #twitter-color-emoji
        #whatsapp-emoji-font

        # Coverage is deliberately LGC-plus only: this user works in
        # FR/DE/LU/NL/EN/PT. Keep Noto's Latin/Greek/Cyrillic faces plus the
        # symbol/music/math families (symbols are still useful for equations,
        # UI glyphs and Nerd Font fallbacks), but do not pull in script fonts
        # for Arabic/CJK/Indic/Thai/etc. — they add size and are unused here.
        noto-fonts-lgc-plus # Noto Sans/Serif/Mono, Music, Symbols, Symbols 2, Math
        noto-fonts-color-emoji # emoji are symbols, used in ordinary text
        vista-fonts # Times New Roman, Arial, Calibri, etc. for MS-doc compatibility
        # WordCraft's equation renderer probes this fallback chain: Cambria
        # Math, STIX Two Math, XITS Math, Libertinus Math, TeX Gyre Termes/
        # Pagella Math, Latin Modern Math, DejaVu Math TeX Gyre, Asana Math,
        # Noto Sans Math. STIX Two and Noto Sans Math already come in above;
        # add the rest so any math face resolves without substitution.
        tex-gyre-math.termes
        tex-gyre-math.pagella
        xits-math
        libertinus
      ];
    };

    # NixOS keeps the system font collection in
    # /run/current-system/sw/share/X11/fonts, but applications that do their own
    # font enumeration (the ArtCraft "Crafting Apps", some Electron apps, etc.)
    # often hard-code the traditional FHS directories /usr/share/fonts and
    # /usr/local/share/fonts. Create symlinks there so those apps see the full
    # system font set instead of only the few faces they embed or find under
    # ~/.local/share/fonts.
    systemd.tmpfiles.rules = [
      "L+ /usr/share/fonts - - - - /run/current-system/sw/share/X11/fonts"
      "L+ /usr/local/share/fonts - - - - /run/current-system/sw/share/X11/fonts"
    ];
  };
}
