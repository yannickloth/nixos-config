# opencode v2 — the post-1.x CLI (https://opencode.ai/v2/docs), published only
# as per-platform prebuilt npm packages under the new @opencode scope
# (@opencode/cli, @opencode/cli-linux-*). nixpkgs' `opencode` still packages the
# 1.x line (1.18.34 at the time of writing), so v2 is packaged in-tree from the
# registry tarball instead.
#
# Each platform tarball ships a single self-contained Bun executable at
# package/bin/opencode (links only glibc: libc/pthread/dl/m), matching what the
# upstream installer at https://opencode.ai/v2/install drops into
# ~/.opencode/bin. autoPatchelfHook repoints the interpreter and shared libs at
# the nix glibc; no build step, no npm tree. The version tracks
# https://opencode.ai/update/api/latest/cli/npm; bump `version` and the two
# hashes together (nix store prefetch-file --hash-type sha256 <url>).
{
  lib,
  stdenv,
  autoPatchelfHook,
  fetchurl,
}:

let
  version = "2.0.29";

  perArch = {
    x86_64-linux = {
      url = "https://registry.npmjs.org/@opencode/cli-linux-x64/-/cli-linux-x64-${version}.tgz";
      hash = "sha256-FLWmY4oaCTrJ1IRZnIRLEMKbRF0EhEtoLMxmjOJlMKI=";
    };
    aarch64-linux = {
      url = "https://registry.npmjs.org/@opencode/cli-linux-arm64/-/cli-linux-arm64-${version}.tgz";
      hash = "sha256-CvOeddvfrMIPj1Me81+03MC0TAgIQgNRhhQnLyMig64=";
    };
  };
in

stdenv.mkDerivation {
  pname = "opencode";
  inherit version;

  src = fetchurl (
    perArch.${stdenv.hostPlatform.system}
      or (throw "opencode v2 has no build for ${stdenv.hostPlatform.system}")
  );

  nativeBuildInputs = [ autoPatchelfHook ];
  # Bun only needs glibc at runtime; libstdc++ comes via stdenv for any
  # unexpected C++ deps the auto patcher trips over.
  buildInputs = [ stdenv.cc.cc.lib ];

  sourceRoot = "package";

  # The opencode binary is a Bun standalone executable: the JS bundle is
  # appended after the ELF image and located via a footer. The default fixup
  # strip corrupts that payload — the binary then runs as a bare Bun
  # interpreter (`opencode --version` prints Bun's 1.4.2 instead of
  # "opencode v2.0.29") — so keep the binary byte-exact after auto-patching.
  dontStrip = true;

  installPhase = ''
    runHook preInstall
    install -Dm0755 bin/opencode $out/bin/opencode
    runHook postInstall
  '';

  meta = with lib; {
    description = "AI coding agent CLI (v2), packaged from the prebuilt npm platform tarball";
    homepage = "https://opencode.ai";
    license = licenses.mit;
    mainProgram = "opencode";
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
    ];
  };
}
