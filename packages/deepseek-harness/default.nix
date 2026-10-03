# deepseek-harness (dsh) — DeepSeek AI's open-source "everything is a plugin"
# agent harness (https://github.com/deepseek-ai/deepseek-harness).
#
# Not in nixpkgs, so build the published npm package `@deepseek-ai/dsh` from the
# registry. The tarball is prebuilt (bundled lib/*.js), so `dontNpmBuild` skips
# the build step and only the runtime dependencies are installed. A generated
# package-lock.json is overlaid onto the tarball so `buildNpmPackage` can resolve
# the ~650-package dependency tree offline (same pattern as
# packages/tools/purescript-language-server).
#
# The bundle boots profiles through `node-addon-require-builtin`, a native addon
# that reverse-engineers V8 internals from a prebuilt napi binary to reach Node's
# internal module loaders. Its scanner does not recognize the nixpkgs Node build
# (the binary loads, then `requireBuiltin` dies with "Unsupported/no-getter"),
# so every profile launch crashes. Node's own `--expose-internals` exposes the
# same modules, so we run `dsh` with that flag and shim the addon to a plain
# `require` (require-builtin-shim.cjs). See the wrapper in postInstall.
#
# `dsh web` serves the Web UI on http://127.0.0.1:3080; `dsh` is the CLI.
{ lib
, fetchurl
, buildNpmPackage
, nodejs
, writeText
, runtimeShell
}:

let
  version = "0.2.0-rc.2";

  # Replaces node-addon-require-builtin at require time. The real addon's
  # `requireBuiltin` is only ever used to obtain internal loaders
  # (internal/modules/{esm,cjs,helpers,utils,resolve}); with --expose-internals
  # a plain `require` returns the same cached internal modules.
  requireBuiltinShim = writeText "dsh-require-builtin-shim.cjs" ''
    'use strict';
    const Module = require('module');
    const originalLoad = Module._load;
    const shim = {
      requireBuiltin: (id) => require(id),
      isAllowedInternalId: (id) => typeof id === 'string' && id.startsWith('internal/'),
      getBindingInfo: () => ({
        mode: 'expose-internals',
        product: 'require-builtin',
        backend: 'js',
        abi: 'none',
      }),
    };
    shim.default = shim;
    Module._load = function (request) {
      if (request === 'node-addon-require-builtin') return shim;
      return originalLoad.apply(this, arguments);
    };
  '';
in
buildNpmPackage {
  pname = "deepseek-harness";
  inherit version;

  src = fetchurl {
    url = "https://registry.npmjs.org/@deepseek-ai/dsh/-/dsh-${version}.tgz";
    hash = "sha256-vSeEfERc1opWWsH5HAa7vMdjnvkwcfZ4u1nF66/ziFk=";
  };

  postPatch = ''
    cp ${./package-lock.json} package-lock.json
  '';

  npmDepsHash = "sha256-BBBTt7EVwE0Vpd8ABO5TlPzhfMshGLkjCrwcz6/hTe4=";

  dontNpmBuild = true;

  # Replace the generated `dsh` launcher with one that boots Node with
  # --expose-internals and preloads the shim (the generated script would fail at
  # profile boot, see the header comment).
  postInstall = ''
    rm -f $out/bin/dsh
    cat > $out/bin/dsh <<'WRAPPER'
    #!${runtimeShell}
    exec ${nodejs}/bin/node --expose-internals --require ${requireBuiltinShim} ${placeholder "out"}/lib/node_modules/@deepseek-ai/dsh/lib/bin.js "$@"
    WRAPPER
    chmod +x $out/bin/dsh
  '';

  meta = with lib; {
    description = "DeepSeek Harness (dsh): an everything-is-a-plugin AI agent harness";
    homepage = "https://github.com/deepseek-ai/deepseek-harness";
    license = licenses.mit;
    mainProgram = "dsh";
    platforms = nodejs.meta.platforms;
  };
}
