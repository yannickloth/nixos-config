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
{
  unstablePkgs,
  hermesAgent,
  browseros,
}:

final: prev: {
  # opencode v2 (2.0.29+, https://opencode.ai/v2): upstream moved past the 1.x
  # line that nixpkgs packages (1.18.34 in the pinned nixpkgs-unstable, 1.19.0
  # in current nixpkgs) and now publishes the CLI only as prebuilt per-platform
  # npm tarballs under the new @opencode scope, so v2 is packaged in-tree
  # (packages/opencode2) from the registry.
  # Upstream's desktop/GUI build is the same v2 release train; nixpkgs'
  # `opencode-desktop` is built from the 1.x monorepo, so it is packaged in-tree
  # too (packages/opencode-desktop, wrapped from the released AppImage).
  # History: v1.18.30/31 crashed on every prompt with a custom provider
  # ("TypeError: undefined is not an object (evaluating 'a.name')") — a circular
  # runtime import between packages/core/src/filesystem.ts and
  # filesystem/search.ts that the Bun 1.4 bundler evaluated in the wrong order,
  # leaving FileSystemSearch.node undefined; fixed upstream in PR #49298
  # (v1.18.32), so the in-tree patch of that era was dropped (see git history /
  # packages/patches). Swap back to `unstablePkgs.opencode` (and delete
  # packages/opencode2) once nixpkgs packages the 2.x line.
  opencode = unstablePkgs.callPackage ../packages/opencode2 { };
  # opencode Desktop: the Electron GUI of the same v2 line, shipped upstream
  # only as per-platform installers (no source build), so it is wrapped in-tree
  # (packages/opencode-desktop) from the released AppImage, like orca/browseros.
  # Self-contained: it bundles its own agent server, so it does not follow the
  # CLI pin above.
  opencode-desktop = unstablePkgs.callPackage ../packages/opencode-desktop { };
  pi-coding-agent = unstablePkgs.pi-coding-agent;
  # herdr (herdr.dev, herdrdev/herdr): Rust terminal multiplexer / runtime that
  # keeps several coding agents (opencode, claude, codex, ...) in the tabs and
  # panes of one persistent session. Not in the stable channel at all (nixos-26.05
  # has no herdr), and the 0.9.x line moves fast, so it comes from unstable like
  # the rest of this list. The per-agent integrations (`herdr integration install
  # opencode`, ...) and the agent skill are handled by packages/herdr/home.nix.
  herdr = unstablePkgs.herdr;
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
  # Open Code Review (ocr): Alibaba's AI code-review CLI. Not in nixpkgs, and
  # its npm wrapper downloads the Go binary at install time, so it is built
  # from the upstream source in-tree (packages/open-code-review). The
  # companion OpenCode plugin (ocr_review tools + /ocr-review slash commands)
  # and the node_modules its SDK imports need are packaged next to it and
  # deployed by users/opencode.nix. NOTE: open-codereview.ai serves no LLM
  # API — `ocr` consumes the providers already configured in opencode, so
  # this is a package + plugin, not a provider entry.
  open-code-review = unstablePkgs.callPackage ../packages/open-code-review { };
  open-code-ocr-plugin = unstablePkgs.callPackage ../packages/open-code-review/plugin-deps.nix { };
  # REA (rea-agents): MCP+CLI reverse-engineering toolkit, published only on
  # npm, packaged in-tree from the registry tarball (packages/rea).
  rea = unstablePkgs.callPackage ../packages/rea { };
  # Orca (ADE): not in nixpkgs and only shipped as a prebuilt Electron AppImage,
  # wrapped as a normal derivation in packages/orca. Exposed here so the adults
  # (nicky, aeiuno) get `pkgs.orca` on every host.
  orca = unstablePkgs.callPackage ../packages/orca { };
  # BrowserOS neo: agent-driven browser that AI assistants drive over MCP with
  # the user's real logins. Packaged in-tree from the upstream AppImage.
  browseros = browseros;
  # JetBrains Toolbox version bump ahead of nixpkgs-unstable. History: in
  # 2026-10 JetBrains moved the Toolbox tarball from download-cdn.jetbrains.com
  # to download.jetbrains.com and nixpkgs-unstable lagged, so the fixed-output
  # source derivation 404'd and the whole switch failed — the override then
  # re-pointed the 3.8.1.88030 source at the working host. nixpkgs has since
  # (rev fe13242281) fixed the URL itself, so the override's only job now is
  # the version bump to 3.9.1.89198 (released 2026-10-30). Drop this override
  # once nixpkgs-unstable carries 3.9.1.
  jetbrains-toolbox =
    let
      newVersion = "3.9.1.89198";
      fixedSrc = unstablePkgs.fetchzip {
        url = "https://download.jetbrains.com/toolbox/jetbrains-toolbox-${newVersion}.tar.gz";
        hash = "sha256-21MTezmZpvxgilxdkFCciUBG6gYi7CYFCYmz2jGcfP4=";
      };
      base = unstablePkgs.jetbrains-toolbox;
    in
    # NOTE: buildFHSEnv embeds `runScript`/`extraInstallCommands` into the
    # wrapper script when it is *called*; `base.overrideAttrs` on the result
    # cannot change them (it only rewrites attrs of the already-generated
    # runCommand derivation), so the version bump has to rebuild the FHS env.
    unstablePkgs.buildFHSEnv {
      pname = "jetbrains-toolbox";
      version = newVersion;
      multiPkgs =
        pkgs:
        with pkgs;
        [ icu libappindicator-gtk3 ] ++ unstablePkgs.appimageTools.defaultFhsEnvArgs.multiPkgs pkgs;
      runScript = "${fixedSrc}/bin/jetbrains-toolbox --update-failed";
      extraInstallCommands = ''
        install -Dm0644 ${fixedSrc}/bin/jetbrains-toolbox.desktop -t $out/share/applications
        install -Dm0644 ${fixedSrc}/bin/toolbox-tray-color.png $out/share/pixmaps/jetbrains-toolbox.png
      '';
      passthru = (base.passthru or { }) // {
        src = fixedSrc;
      };
      meta = base.meta;
    };
  vscode = unstablePkgs.vscode;
}
