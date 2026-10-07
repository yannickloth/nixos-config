# Overlay that swaps the fast-moving, AI-heavy tooling to unstable nixpkgs
# builds. Applied per-user (nicky, aeiuno) by both the root flake's
# home-manager module and the standalone users/flake.nix, so every host gives
# the adults bleeding-edge AI tooling while kids stay on stable nixpkgs.
#
# Example: the opencode / pi-coding-agent / jetbrains-toolbox / vscode you get
# on a stable channel lag unstable by weeks-to-months. These move fast because
# of built-in AI features, so they are pulled from nixos-unstable. hermes-agent,
# magpie and deepseek-harness are not in nixpkgs at all and are packaged in-tree
# (packages/hermes-agent, packages/magpie, packages/deepseek-harness).
{ unstablePkgs, hermesAgent }:

final: prev: {
  # opencode 1.18.30/1.18.31 crashed on every prompt when the config declared
  # any custom provider: "TypeError: undefined is not an object (evaluating
  # 'a.name')" / "Unexpected server error". Root cause was a circular runtime
  # import between packages/core/src/filesystem.ts and filesystem/search.ts,
  # which the newer Bun bundler (1.4.x) evaluated in the order that left
  # FileSystemSearch.node undefined. Upstream fixed it in anomalyco/opencode
  # PR #49298 (v1.18.32), and nixpkgs-unstable now ships 1.18.34, so the
  # in-tree patch was dropped (see git history / packages/patches).
  opencode = unstablePkgs.opencode;
  pi-coding-agent = unstablePkgs.pi-coding-agent;
  # Hermes Agent is packaged in-tree (packages/hermes-agent) from upstream's
  # uv.lock via uv2nix — it is not in nixpkgs at all.
  hermes-agent = hermesAgent;
  # magpie (yetone/magpie): menu-bar/TUI/CLI model switcher and the local
  # gateway every agent points at. Packaged in-tree (packages/magpie) and built
  # with unstable's Go, which go.mod requires (>= 1.26.3).
  magpie = unstablePkgs.callPackage ../packages/magpie { };
  # DeepSeek Harness (dsh): agent harness published only on npm, packaged
  # in-tree from the registry tarball (packages/deepseek-harness).
  deepseek-harness = unstablePkgs.callPackage ../packages/deepseek-harness { };
  # Orca (ADE): not in nixpkgs and only shipped as a prebuilt Electron AppImage,
  # wrapped as a normal derivation in packages/orca. Exposed here so the adults
  # (nicky, aeiuno) get `pkgs.orca` on every host.
  orca = unstablePkgs.callPackage ../packages/orca { };
  # JetBrains moved the Toolbox tarball from download-cdn.jetbrains.com to
  # download.jetbrains.com (2026-10); nixpkgs-unstable still fetches the dead
  # CDN host, so the fixed-output source derivation 404s and the whole switch
  # fails. The same version still 200s at the new host with byte-identical
  # contents (same output hash), so re-point the source — and the runScript /
  # install commands, which embed its store path — at the working host. Drop
  # this override once nixpkgs updates the URL upstream.
  jetbrains-toolbox =
    let
      fixedSrc = unstablePkgs.fetchzip {
        url = "https://download.jetbrains.com/toolbox/jetbrains-toolbox-3.8.1.88030.tar.gz";
        hash = "sha256-OsuSgC22E2hurQCEnev8GA8hQWLaxg6hclPYHm8crWc=";
      };
      base = unstablePkgs.jetbrains-toolbox;
    in
    base.overrideAttrs (old: {
      runScript = "${fixedSrc}/bin/jetbrains-toolbox --update-failed";
      extraInstallCommands = ''
        install -Dm0644 ${fixedSrc}/bin/jetbrains-toolbox.desktop -t $out/share/applications
        install -Dm0644 ${fixedSrc}/bin/toolbox-tray-color.png -t $out/share/icons/hicolor/32x32/apps/jetbrains-toolbox.png
      '';
      passthru = (old.passthru or { }) // {
        src = fixedSrc;
      };
    });
  vscode = unstablePkgs.vscode;
}
