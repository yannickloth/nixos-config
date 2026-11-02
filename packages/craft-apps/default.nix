# ArtCraft "Crafting Apps" (https://getartcraft.com/apps): thirteen pure-Rust,
# clean-room reimplementations of familiar creative tools, published by
# storytold as prebuilt Linux AppImages (no source build we want to pay for:
# each is a large Rust + wgpu workspace).
#
# Every app is wrapped with appimageTools.wrapType2, so the result is a normal,
# hash-pinned, immutable derivation that cannot self-update and never writes its
# launcher into ~/.local/share. The desktop entry, hicolor icons, MIME types and
# AppStream metadata the bundle carries are installed so the launcher shows the
# real name and icon.
#
# Host-specific graphics/audio stack (the `cachyos` flag):
#   nixpkgs' defaultFhsEnvArgs ships the GPU *loaders* only (vulkan-loader,
#   libglvnd's libGL/libEGL) and expects the drivers, their Vulkan ICD JSONs and
#   the glvnd EGL vendor JSON from /run/opengl-driver — a NixOS-only path that
#   hardware.graphics populates. On NixOS that is enough, so the default build
#   (cachyos = false) stays plain. The standalone CachyOS deployment
#   (users/flake.nix, laptop-p16) has no /run/opengl-driver, so there wgpu
#   enumerated no adapter and every app died with
#   "Wgpu(CreateSurfaceError(CreateSurfaceError { inner:
#   Hal(FailedToCreateSurfaceForAnyBackend({})) }))"; it needs Mesa bundled,
#   VA-API for hardware video decode, and an ALSA setup matching its
#   PipeWire/PulseAudio host. All of that is gated behind cachyos = true so the
#   NixOS hosts (which use /run/opengl-driver) keep the plain config.
#
# Update one app: `nix-update --flake <pname>` bumps version + hash together.
# Run it one app per invocation, never in a loop over several apps: with two
# apps still pinning the same version string, its blind file-wide string
# replacement overwrites the OTHER app's version line (recovered this way once
# on 2026-10-29; hashes were unaffected because they are unique strings).
# Each AppImage also ships a `<pname>-cli` headless agent; it is not exposed
# here — the desktop apps are the goal, and each CLI would need its own FHS-run
# wrapper. See git history if that is wanted later.
{
  lib,
  appimageTools,
  fetchurl,
  # Bundle the host-specific graphics/audio stack described above. Set only by
  # the CachyOS deployment (users/common-hm.nix passes commonHm.isCachyOS, which
  # is laptop-p16's standalone flake); the default false relies on the system's
  # drivers (/run/opengl-driver on NixOS) and system ALSA config.
  cachyos ? false,
}:

let
  # pipewire ships its ALSA plugin config under share/alsa/alsa.conf.d, which
  # alsa-lib does not read (it hooks /etc/alsa/conf.d). Repackage it as
  # etc/alsa/conf.d so buildFHSEnv's buildEnv merges it into the FHS /etc next
  # to alsa-plugins' confs; otherwise opening ALSA's default/"pipewire" PCM
  # fails with "Unknown PCM pipewire" even though the plugin is present.
  pipewireAlsaConf =
    pkgs:
    pkgs.runCommand "pipewire-alsa-conf" { } ''
      mkdir -p $out/etc/alsa/conf.d
      for name in 50-pipewire.conf 99-pipewire-default.conf; do
        cp "$(find ${pkgs.pipewire} -name "$name" -print -quit)" "$out/etc/alsa/conf.d/$name"
      done
    '';

  # Host-specific runtime extras, only bundled when cachyos = true.
  cachyosExtras = pkgs: [
    # GPU drivers + Vulkan ICDs + glvnd EGL vendor JSON + llvmpipe fallback.
    pkgs.mesa
    # ALSA plugins: the rate-lav/speexrate hooks and pulse/jack/oss PCMs.
    pkgs.alsa-plugins
    # PipeWire ALSA PCM config; the plugin itself ships with pipewire (in the
    # default FHS env).
    (pipewireAlsaConf pkgs)
    # VA-API hardware video decode (FilmCraft, LightCraft): libva plus the
    # Intel iHD driver. libva's compiled driver path includes /usr/lib/dri,
    # which the FHS env maps to /usr/lib64/dri where the driver is merged.
    pkgs.libva
    pkgs.intel-media-driver
  ];

  mkCraftApp =
    {
      pname,
      version,
      hash,
      description,
    }:
    let
      src = fetchurl {
        url = "https://github.com/storytold/${pname}/releases/download/v${version}/${pname}-${version}-linux-x86_64.AppImage";
        # x86_64 build only; upstream ships -linux-aarch64.AppImage too.
        inherit hash;
      };

      # Extract the AppImage a second time (wrapType2's internal extraction is
      # the same derivation) so extraInstallCommands can install the bundle's
      # desktop entry, hicolor icons, MIME types and AppStream metadata.
      appimageContents = appimageTools.extract {
        inherit pname version src;
      };
    in
    appimageTools.wrapType2 {
      inherit pname version src;

      # Empty unless cachyos = true; see the header and cachyosExtras.
      extraPkgs = pkgs: if cachyos then cachyosExtras pkgs else [ ];

      # wrapType2 exposes only bin/<pname>, dropping everything else the bundle
      # carries. Copy it back wholesale. Upstream names each file
      # ai.storyteller.<pname> and sets Exec=<pname>, which matches the wrapped
      # binary, so no substitution is needed.
      extraInstallCommands = ''
        mkdir -p $out/share
        for dir in applications icons mime metainfo; do
          if [ -d "${appimageContents}/usr/share/$dir" ]; then
            cp -r "${appimageContents}/usr/share/$dir" "$out/share/"
          fi
        done
      '';

      meta = with lib; {
        inherit description;
        homepage = "https://getartcraft.com/apps/${pname}";
        license = with licenses; [
          mit
          asl20
        ];
        mainProgram = pname;
        # The pinned URL is the x86_64 AppImage specifically; do not advertise
        # aarch64-linux as available.
        platforms = [ "x86_64-linux" ];
        sourceProvenance = with sourceTypes; [ binaryNativeCode ];
      };
    };
in
{
  photocraft = mkCraftApp {
    pname = "photocraft";
    version = "0.18.0";
    hash = "sha256-gwdXrK6Htd6iDyUgA5LeEYoUOjXcG1IEGjUmEgJn5oQ=";
    description = "Image editor: layers, masks, adjustment layers, type, vectors and real PSD files (clean-room Photoshop reimplementation)";
  };

  vectorcraft = mkCraftApp {
    pname = "vectorcraft";
    version = "0.19.0";
    hash = "sha256-GGlVS6/UKNs7No+kBbirSIsl0yTTgOdyvAsRi7rLNMU=";
    description = "Vector illustration: SVG and PDF drawing (clean-room Illustrator reimplementation)";
  };

  filmcraft = mkCraftApp {
    pname = "filmcraft";
    version = "0.15.0";
    hash = "sha256-S8sRnBqmDfVM4zONeqSOPxTWFWn3vGOFGgC9yJJJZHs=";
    description = "Non-linear video editor (clean-room Premiere Pro reimplementation)";
  };

  lightcraft = mkCraftApp {
    pname = "lightcraft";
    version = "0.16.0";
    hash = "sha256-DKHp5YUAjKbAAnFoq8bfJqGgyuiybXMYG7U+LOMuXXc=";
    description = "Photo library and raw developer (clean-room Lightroom reimplementation)";
  };

  pdfcraft = mkCraftApp {
    pname = "pdfcraft";
    version = "0.16.1";
    hash = "sha256-JTWmipwhVpRsvHzT/+RwSj0shAohHObMLZzqYtNtylM=";
    description = "PDF workbench: read, organize, combine, split and secure";
  };

  effectcraft = mkCraftApp {
    pname = "effectcraft";
    version = "0.19.0";
    hash = "sha256-nIuMWzPx8EJA3q68hUzFO5l82kjPKezXFztDyYBJ8ME=";
    description = "Motion graphics and visual effects (clean-room After Effects reimplementation)";
  };

  designcraft = mkCraftApp {
    pname = "designcraft";
    version = "0.15.2";
    hash = "sha256-bUbhD458J0a22qTFZcbGqFMpweYZLgqgu/UmupGj76A=";
    description = "Page layout and publishing (clean-room InDesign reimplementation)";
  };

  figcraft = mkCraftApp {
    pname = "figcraft";
    version = "0.13.1";
    hash = "sha256-L6RO/fSHjep+t5sSJ/J0vMspiqtkMdeNDoNw6mwSVHQ=";
    description = "Interface design and prototyping (clean-room Figma reimplementation)";
  };

  wordcraft = mkCraftApp {
    pname = "wordcraft";
    version = "0.13.2";
    hash = "sha256-8l1Ox7568z/PRQAtm3UOxzURfETaMELgQ655NX1ERTM=";
    description = "Word processing (clean-room Microsoft Word reimplementation)";
  };

  soundcraft = mkCraftApp {
    pname = "soundcraft";
    version = "0.15.0";
    hash = "sha256-EHpZf9P21F2SEEevJ05VDe3u+017yME+w2iAkTCfgSY=";
    description = "Digital audio workstation: recording, editing and mixing (clean-room Pro Tools reimplementation)";
  };

  deckcraft = mkCraftApp {
    pname = "deckcraft";
    version = "0.13.1";
    hash = "sha256-4sv5Nzj8swj+nMhCLeB/tgkFc0FW39VrN3/Sp4qRiyA=";
    description = "Presentations and slide shows (clean-room PowerPoint reimplementation)";
  };

  cadcraft = mkCraftApp {
    pname = "cadcraft";
    version = "0.15.1";
    hash = "sha256-iK5haVhBO4+lYlnfb3D7aVq5C0cuTGPPlVrmpkcbsR0=";
    description = "Computer-aided design and drafting (clean-room AutoCAD reimplementation)";
  };

  gridcraft = mkCraftApp {
    pname = "gridcraft";
    version = "0.14.2";
    hash = "sha256-B0DyFDObOGq0XAdv6fb2TkmGxWwh2PvWu+XQvgPufys=";
    description = "Spreadsheets and data analysis (clean-room Excel reimplementation)";
  };
}
