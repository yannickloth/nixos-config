# purescript-language-server (https://github.com/nwolverson/purescript-language-server)
#
# Not packaged in nixpkgs, so build the published npm tarball here. The tarball
# is prebuilt (the bundled `server.js` is committed), so no `npm run build` is
# needed — only the runtime npm dependencies are installed. A generated
# package-lock.json is overlaid onto the tarball so `buildNpmPackage` can
# resolve dependencies offline.
{ lib
, fetchurl
, buildNpmPackage
, nodejs
}:

let
  version = "0.18.5";
  src = fetchurl {
    url = "https://registry.npmjs.org/purescript-language-server/-/purescript-language-server-${version}.tgz";
    hash = "sha256-K0pVq07nHdo/n+spBDfc8riwgzRMq4SQCJ1sqrEjNB0=";
  };
in
buildNpmPackage {
  pname = "purescript-language-server";
  inherit version src;

  postPatch = ''
    cp ${./package-lock.json} package-lock.json
  '';

  npmDepsHash = "sha256-8CpI5ilOngk5u48ejpqPT0lPxWSdxEfvu6TOokxe3q4=";

  dontNpmBuild = true;

  # `npm pack` runs the `prepare` script, which wants spago/purescript to
  # rebuild; the published tarball is already bundled, so skip all scripts.
  npmPackFlags = [ "--ignore-scripts" ];

  meta = with lib; {
    description = "Language server for PureScript";
    homepage = "https://github.com/nwolverson/purescript-language-server";
    license = licenses.mit;
    maintainers = [ ];
    platforms = nodejs.meta.platforms;
  };
}
