# LibreOffice MCP extension (quazardous/mcp-libre) as a plain .oxt artifact.
#
# LibreOffice extensions are not NixOS packages: an .oxt is deployment data that
# `unopkg` copies into the *user* profile
# (~/.config/libreoffice/4/user/uno_packages/cache), and LibreOffice only picks
# it up from there. So this derivation carries the pinned release artifact and
# ./home.nix registers it at activation time.
#
# `port` is patched into the artifact instead of the LibreOffice profile: the
# extension resolves it only from its own configuration schema/data layer, and
# the user layer that overrides it (registrymodifications.xcu) is rewritten by
# LibreOffice itself, so it cannot be managed declaratively. Patching the
# shipped default makes the port a build-time, per-user property. This matters
# on a shared host: two LibreOffice instances on the same port do not collide
# loudly — `_probe_health` accepts any "LibreOffice MCP" answer on the port, so
# the second instance concludes a healthy server is "already running" and never
# starts its own, leaving both users' MCP clients talking to the first user's
# documents.
#
# `Host` is patched to 127.0.0.1 and is deliberately NOT an option: the endpoint
# is local-only. Upstream defaults it to the name "localhost", which on a host
# that lists `::1 localhost` first is an IPv6 address the server does not bind
# (it listens on IPv4 loopback), so clients only reach it through Happy Eyeballs
# fallback. Pinning the numeric loopback address makes the client URL and the
# listening socket agree by construction, and keeps the surface loopback-only —
# no tunnel (upstream's Tailscale/bore/cloudflared/ngrok support stays disabled)
# and no LAN binding is ever intended here.
#
# Upstream note: quazardous/mcp-libre is archived and points at "Nelson MCP" as
# its successor. v2.4.0 is the last release of this extension and the version
# that is verified against the LibreOffice in nixpkgs (25.8); bump
# `version`/`hash` together if a successor is adopted.
{
  lib,
  stdenvNoCC,
  fetchurl,
  unzip,
  zip,
  port ? 8765,
}:

stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "libreoffice-mcp-extension";
  version = "2.4.0";

  src = fetchurl {
    url = "https://github.com/quazardous/mcp-libre/releases/download/v${finalAttrs.version}/libreoffice-mcp-extension.oxt";
    hash = "sha256-9tJEt55BldGk0ToSaMLM0aFiwaR8yijCiJSI0TndSCI=";
  };

  nativeBuildInputs = [
    unzip
    zip
  ];

  dontUnpack = true;
  # Nothing to make; only the repack step below.
  dontBuild = true;

  installPhase = ''
    runHook preInstall

    mkdir ext
    unzip -q $src -d ext
    # MCPServerConfig.xcu is the extension's shipped data layer; it is the only
    # place the default port lives (no env var, no CLI flag).
    substituteInPlace ext/MCPServerConfig.xcu \
      --replace-fail '<value>8765</value>' '<value>${builtins.toString port}</value>' \
      --replace-fail '<value>localhost</value>' '<value>127.0.0.1</value>'

    install -d $out/lib
    ( cd ext && zip -qr -X $out/lib/libreoffice-mcp-extension.oxt . )

    runHook postInstall
  '';

  meta = {
    description = "MCP server embedded in LibreOffice (Writer/Calc/Impress tools over streamable HTTP)";
    homepage = "https://github.com/quazardous/mcp-libre";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
  };
})
