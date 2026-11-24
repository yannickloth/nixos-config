# ArtCraft "Crafting Apps" (https://getartcraft.com/apps): seventeen pure-Rust,
# clean-room reimplementations of familiar creative tools, published by
# storytold as per-platform tarballs (no source build we want to pay for: each
# is a large Rust + wgpu workspace).
#
# Every app lands in its own derivation that installs:
#   $out/bin/<app>         — the GUI app: a wrapper (see below) around the
#                            real binary <app>.bin (wgpu/OpenGL rendering)
#   $out/bin/<app>-cli     — headless agent (MCP server, scripting, exports),
#                            likewise a wrapper around <app>-cli.bin
#   $out/share/applications/ — desktop entry (Exec=<pname> resolves via PATH)
#   $out/share/icons/hicolor/  — hicolor icon set at multiple sizes
#   $out/share/metainfo/       — AppStream metainfo (flatpak store listings)
#   $out/share/mime/packages/  — MIME type registration
#
# Update one app: `nix-update --flake <pname>` bumps version + hash together.
# Run it one app per invocation, never in a loop over several apps: with two
# apps still pinning the same version string, its blind file-wide string
# replacement overwrites the OTHER app's version line (recovered this way once
# on 2026-10-29; hashes were unaffected because they are unique strings).
#
# The tarball bundles both the GUI and CLI binaries. The CLI is useful for MCP
# integration (designcraft-cli mcp, photocraft-cli mcp, etc.) — previously
# hidden inside the AppImage FHS sandbox. No FHS extras, no CachyOS flags.
#
# The binaries are linked against a distro glibc: their ELF interpreter is
# /lib64/ld-linux-x86-64.so.2 (a stub on NixOS, hence "NixOS cannot run
# dynamically linked executables ... out of the box") and their NEEDED set is
# libc.so.6 + libm.so.6 + libgcc_s.so.1 (libasound.so.2 on the audio apps),
# with no RPATH. The GUIs additionally dlopen their whole display/rendering
# stack at run time (wayland, xkbcommon, the Vulkan loader, EGL, xcb/X11,
# gbm/drm, and mesa + libLLVM for the OpenGL fallback); soundcraft forces the
# X11 backend and so also needs the x11-dl extension libraries.
#
# So every binary is patched to use NixOS's glibc dynamic linker, then installed
# as <name>.bin plus a tiny <name> wrapper that sets LD_LIBRARY_PATH to the
# runtime stack (runtimeLibs below) and execs the real binary. Using the normal
# kernel loader instead of invoking ld-linux-x86-64.so.2 directly is required:
# some Craft binaries (notably PhotoCraft) have internal startup logic that
# breaks when they are launched through the dynamic linker as if they were a
# shared object, causing every command-line argument to be misinterpreted.
# GPU driver libraries are deliberately NOT in LD_LIBRARY_PATH: the Vulkan ICD
# and EGL vendor dispatch resolve them through the system's own
# /run/opengl-driver mechanisms, so the wrapper follows the host's driver. It
# uses the system Vulkan drivers from /run/opengl-driver on NixOS
# (provided by hardware.graphics.enable), or falls back to OpenGL/mesa
# software rendering.
{ pkgs
,
}:

let
  inherit (pkgs) lib fetchurl stdenvNoCC glibc patchelf;

  # Runtime library search path for the wrappers (see file header): glibc
  # covers the NEEDED set (nixpkgs builds libgcc_s inside glibc); alsa-lib
  # the audio apps; the rest what the GUIs dlopen at run time, ending in the
  # mesa/LLVM chain behind the OpenGL fallback (libgallium NEEDs libLLVM and
  # libstdc++, so both must be reachable even on GPU hosts, where the EGL
  # vendor dispatch loads mesa alongside the GPU vendor).
  runtimeLibs = with pkgs; [
    glibc
    alsa-lib
    wayland
    libxkbcommon
    vulkan-loader
    libglvnd
    libxcb
    # X11 + x11-dl's dlopen set for winit's X11 backend: some apps
    # (soundcraft) build winit with the backend forced to X11, so this must
    # resolve too. Top-level libx* names: the xorg.* aliases are deprecated
    # in 26.05 and the build warns on every evaluation.
    libx11
    libxau
    libxdmcp
    libxext
    libxfixes
    libxi
    libxrandr
    libxrender
    libxcursor
    libxtst
    expat
    zlib
    zstd
    xz
    bzip2
    libxml2
    libdrm
    mesa
    libgbm
    libffi
    libpciaccess
    lm_sensors
    libxshmfence
    elfutils
    llvmPackages_21.llvm.lib
    gcc.cc.lib
    systemdMinimal
    dbus.lib
  ];

  libraryPath = builtins.concatStringsSep ":" (map (d: "${d}/lib") runtimeLibs);

  mkCraftApp =
    { pname
    , version
    , hash
    , description
    ,
    }:
    let
      src = fetchurl {
        url = "https://github.com/storytold/${pname}/releases/download/v${version}/${pname}-${version}-linux-x86_64.tar.gz";
        # x86_64 build only; upstream ships -linux-aarch64.tar.gz and .deb/.rpm too.
        inherit hash;
      };
    in
    stdenvNoCC.mkDerivation {
      inherit pname version src description;

      nativeBuildInputs = [ patchelf ];

      # The tarball extracts into <pname>-<version>-linux-x86_64/ with a
      # conventional layout: bin/, share/applications/, share/icons/hicolor/,
      # share/metainfo/, share/mime/packages/.

      installPhase = ''
                mkdir -p $out/bin $out/share/applications $out/share/icons/hicolor \
                         $out/share/metainfo $out/share/mime/packages
                # Copy both GUI and CLI binaries verbatim
                cp bin/* $out/bin/

                # Patch each ELF to use NixOS's glibc dynamic linker and wrap it with
                # an LD_LIBRARY_PATH script (see file header for why). The heredoc body
                # is column-0 (shebangs must start at byte 0). Note this is an indented
                # Nix string, where a lone backslash is literal, and the build-time
                # heredoc must see \$@ to keep "$@" out of expansion (inside a phase
                # $@ is the phase name itself, so never leave it bare here).
                for f in $out/bin/*; do
                  # Only wrap real ELF executables; leave anything else upstream
                  # might ever ship in bin/ untouched.
                  [ "$(head -c 4 "$f" | od -An -tx1 | tr -d ' \n')" = "7f454c46" ] || continue
                  mv "$f" "$f.bin"
                  patchelf --set-interpreter ${glibc}/lib/ld-linux-x86-64.so.2 "$f.bin"
                  cat > "$f" <<EOF
        #!${stdenvNoCC.shell}
        export LD_LIBRARY_PATH="${libraryPath}${"\${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"}"
        exec "$f.bin" "\$@"
        EOF
                  chmod +x "$f"
                done

                # Desktop entry: Exec=<pname> already resolves via ~/.nix-profile/bin/
                # which the desktop environment has in PATH. No substitution needed.
                cp share/applications/*.desktop $out/share/applications/

                # Icons, metainfo (AppStream), MIME types — metainfo and MIME types
                # are optional; craft-anything ships neither, so the copy loops
                # guard on file existence to avoid "missing destination file operand"
                # when the glob expands to nothing (failing under set -e).
                cp -r share/icons/hicolor/* $out/share/icons/hicolor/
                for f in share/metainfo/*.xml; do
                  [ -e "$f" ] && cp "$f" $out/share/metainfo/
                done
                for f in share/mime/packages/*.xml; do
                  [ -e "$f" ] && cp "$f" $out/share/mime/packages/
                done
                if [ -d share/thumbnailers ]; then
                  mkdir -p $out/share/thumbnailers
                  cp share/thumbnailers/* $out/share/thumbnailers/
                fi
                if [ -d share/doc/${pname} ]; then
                  mkdir -p $out/share/doc/${pname}
                  cp -r share/doc/${pname}/* $out/share/doc/${pname}/
                fi
      '';

      # Preserve debug symbols for crash reports / coredumps
      dontStrip = true;

      meta = with lib; {
        inherit description;
        homepage = "https://getartcraft.com/apps/${pname}";
        license = with licenses; [
          mit
          asl20
        ];
        mainProgram = pname;
        # Upstream only ships x86_64 Linux; do not advertise aarch64 as
        # available even though the URL pattern supports it.
        platforms = [ "x86_64-linux" ];
        sourceProvenance = with sourceTypes; [ binaryNativeCode ];
      };
    };
in
{
  photocraft = mkCraftApp {
    pname = "photocraft";
    version = "0.23.1";
    hash = "sha256-Q4Ou9noHzDcK0lCm7WABUgXT5sRj+vP/Sw9nuBeMz8g=";
    description = "Image editor: layers, masks, adjustment layers, type, vectors and real PSD files (clean-room Photoshop reimplementation)";
  };

  vectorcraft = mkCraftApp {
    pname = "vectorcraft";
    version = "0.24.1";
    hash = "sha256-oJBRQlL94UVJWsb8Zdb/ExHWmJmOV7pDTV0IlsPR+/o=";
    description = "Vector illustration: SVG and PDF drawing (clean-room Illustrator reimplementation)";
  };

  filmcraft = mkCraftApp {
    pname = "filmcraft";
    version = "0.20.1";
    hash = "sha256-Pk/qPLjUc+aPGJoKh5K6RhYPq1B62rOriSAHP9QfJPo=";
    description = "Non-linear video editor (clean-room Premiere Pro reimplementation)";
  };

  lightcraft = mkCraftApp {
    pname = "lightcraft";
    version = "0.21.1";
    hash = "sha256-sSPeFpFYCaeeZLpO467p4c3tbvI7c3wG+Bzcfi8obWI=";
    description = "Photo library and raw developer (clean-room Lightroom reimplementation)";
  };

  pdfcraft = mkCraftApp {
    pname = "pdfcraft";
    version = "0.22.0";
    hash = "sha256-qJk/nuluh6zOz5CvQib/YKhLnheHrp/Y+kj/4Tlrw14=";
    description = "PDF workbench: read, organize, combine, split and secure";
  };

  effectcraft = mkCraftApp {
    pname = "effectcraft";
    version = "0.25.1";
    hash = "sha256-byn/fgNZkJ/h2/b9PP2EMKA2I0m2EsXrLPyP7nueJ2A=";
    description = "Motion graphics and visual effects (clean-room After Effects reimplementation)";
  };

  anicraft = mkCraftApp {
    pname = "anicraft";
    version = "0.2.1";
    hash = "sha256-o6h5W9aupLS8XKDybCJqByMw04/pP07fVSY2Dr9xVv0=";
    description = "2D vector animation: timeline, tweens, symbols, buttons and ActionScript (clean-room Adobe Animate reimplementation)";
  };

  designcraft = mkCraftApp {
    pname = "designcraft";
    version = "0.21.1";
    hash = "sha256-IR50ufXO5b/DzbRpg9C9sf29CRZL/YB/T/cHBpNdQK4=";
    description = "Page layout and publishing (clean-room InDesign reimplementation)";
  };

  figcraft = mkCraftApp {
    pname = "figcraft";
    version = "0.18.1";
    hash = "sha256-gnbSrFXG939686QRqbAEFdP+sLWWB6VFIzETQOZT/Bk=";
    description = "Interface design and prototyping (clean-room Figma reimplementation)";
  };

  texturecraft = mkCraftApp {
    pname = "texturecraft";
    version = "0.6.1";
    hash = "sha256-4X0Uoeu59hHaRhcIwpiIdQ+YL91/DNEeFpDsSoQGhgA=";
    description = "3D texture painting: paint PBR materials onto models in layers, bake mesh maps and export for any engine";
  };

  materialcraft = mkCraftApp {
    pname = "materialcraft";
    version = "0.4.1";
    hash = "sha256-QxFfjT4v7o+fKbwHsDyYTC6PbQTg4ZWUOdc+xc32gw4=";
    description = "Node-based procedural materials: tileable PBR maps from noises, patterns and filters with live 2D/3D preview";
  };

  wordcraft = mkCraftApp {
    pname = "wordcraft";
    version = "0.18.1";
    hash = "sha256-MSoFfUbdgFl8EtzP0Ql84l7epAuqrrULy28BrBrrrbU=";
    description = "Word processing (clean-room Microsoft Word reimplementation)";
  };

  soundcraft = mkCraftApp {
    pname = "soundcraft";
    version = "0.20.1";
    hash = "sha256-yu/PhcTxE4cX1ZLTHOW+B/L8phbsNtY/rGdgze++KKk=";
    description = "Digital audio workstation: recording, editing and mixing (clean-room Pro Tools reimplementation)";
  };

  deckcraft = mkCraftApp {
    pname = "deckcraft";
    version = "0.18.1";
    hash = "sha256-W659VWZjhiRBHvlo8lMqszWNwoCIQURYPkl8VjHbiiY=";
    description = "Presentations and slide shows (clean-room PowerPoint reimplementation)";
  };

  cadcraft = mkCraftApp {
    pname = "cadcraft";
    version = "0.20.1";
    hash = "sha256-V7bxtBtPPFQqgvEDIC7Rp3lEDl/40lwI72ar2hqMsbk=";
    description = "Computer-aided design and drafting (clean-room AutoCAD reimplementation)";
  };

  gridcraft = mkCraftApp {
    pname = "gridcraft";
    version = "0.19.1";
    hash = "sha256-jZe7otW7AP1p7VUGSFLB/ZFN5A1ezVXKAcjfgbgolG0=";
    description = "Spreadsheets and data analysis (clean-room Excel reimplementation)";
  };

  craft-anything = mkCraftApp {
    pname = "craft-anything";
    version = "0.6.1";
    hash = "sha256-g+wHMMkRfzmRIrMVxj7Uw6jTGsVb3ddMuLM80vdu9wQ=";
    description = "Software exploration and creation: study websites, apps, games and files, then build your own version with a coding agent";
  };
}
