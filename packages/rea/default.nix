# REA (rea-agents) — "reverse engineer anything" agent toolkit
# (https://github.com/morluto/rea, https://rea.tools). Registers an MCP server
# and CLI for inspecting native binaries, JS/Electron apps, .NET assemblies,
# websites and more.
#
# Not in nixpkgs and only published on npm, so build the registry tarball of
# `rea-agents`. The published tarball already ships the compiled `dist/` (the
# `prepack`/`prepare` scripts run at publish time), so `dontNpmBuild` skips the
# build and only the runtime dependencies are installed. A generated
# package-lock.json (npm install --package-lock-only, --ignore-scripts) is
# committed so `buildNpmPackage` can resolve the ~720-package tree offline, the
# same pattern as packages/deepseek-harness.
#
# Provides the `rea` (and `rea-agents`) commands: `rea mcp` serves the MCP
# server over stdio; `rea --help` lists the CLI. Native analysis optionally
# uses a caller-supplied Hopper/Ghidra/IDA; the browser tools use a
# caller-supplied Chromium (playwright-core only, no browser is bundled).
{ lib
, fetchurl
, buildNpmPackage
, nodejs
}:

buildNpmPackage {
  pname = "rea";
  version = "6.8.0";

  src = fetchurl {
    url = "https://registry.npmjs.org/rea-agents/-/rea-agents-6.8.0.tgz";
    hash = "sha256-jVQux2qcs1BYS2CmycCIcG/4EtW7WwlMIMlbbcJWmLs=";
  };

  postPatch = ''
    cp ${./package-lock.json} package-lock.json
  '';

  npmDepsHash = "sha256-alfU1v1u/70UzS2w39c6xVckSMhO9li+cjJoyexr3Lg=";

  dontNpmBuild = true;

  # `npm ci` already runs with --ignore-scripts inside buildNpmPackage, but the
  # `npm rebuild` that follows it does not. rea 6.5.0 adds the optional `frida`
  # binding whose install script downloads a prebuilt native toolchain, which
  # the sandbox forbids (`npm error path node_modules/frida ... Downloading
  # toolchain`); --ignore-scripts covers both commands. Nothing in the runtime
  # tree needs compiling: @lydell/node-pty and esbuild ship their platform
  # binaries as optional dependencies, and rea imports frida lazily
  # (dist/frida/FridaInstrumentationManager.js, `await import("frida")`), so
  # the missing native binding only disables its frida-backed tools.
  npmFlags = [ "--ignore-scripts" ];
  # `npm rebuild` (buildNpmPackage's install step) does not inherit npmFlags.
  npmRebuildFlags = [ "--ignore-scripts" ];

  meta = with lib; {
    description = "Reverse engineer anything with agents, from app behavior down to native binaries";
    homepage = "https://github.com/morluto/rea";
    license = licenses.mit;
    mainProgram = "rea";
    platforms = nodejs.meta.platforms;
  };
}
