# REA (rea-agents) — "reverse engineer anything" agent toolkit
# (https://github.com/morluto/rea, https://rea.tools). Registers an MCP server
# and CLI for inspecting native binaries, JS/Electron apps, .NET assemblies,
# websites and more.
#
# Not in nixpkgs and only published on npm, so build the registry tarball of
# `rea-agents`. The published tarball already ships the compiled `dist/` (the
# `prepack`/`prepare` scripts run at publish time), so `dontNpmBuild` skips the
# build and only the runtime dependencies are installed. A generated
# package-lock.json (npm install --package-lock-only) is committed so
# `buildNpmPackage` can resolve the ~540-package tree offline, the same pattern
# as packages/deepseek-harness.
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
  version = "6.4.0";

  src = fetchurl {
    url = "https://registry.npmjs.org/rea-agents/-/rea-agents-6.4.0.tgz";
    hash = "sha256-WesWBLjbdfUi1Kl1w2zmtKKtRl5DutFl+aj3KDkdubg=";
  };

  postPatch = ''
    cp ${./package-lock.json} package-lock.json
  '';

  npmDepsHash = "sha256-3Qbd+ohtaYSqDxZy+Spwdebd0jOdWcGVHXPWg/srID0=";

  dontNpmBuild = true;

  meta = with lib; {
    description = "Reverse engineer anything with agents, from app behavior down to native binaries";
    homepage = "https://github.com/morluto/rea";
    license = licenses.mit;
    mainProgram = "rea";
    platforms = nodejs.meta.platforms;
  };
}
