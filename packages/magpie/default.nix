# magpie (yetone/magpie) — "every agent's model, one place": a TUI/CLI tool
# (and optional menu-bar app) that points Codex/Claude Code/opencode/... at
# one local gateway (127.0.0.1:3425) and one model catalog.
#
# Not in nixpkgs, so it is packaged in-tree from the upstream source.
#
# This build is the terminal-only (`nogui`) variant. The GUI build links GTK 3
# + WebKitGTK 4.1 through cgo, but on this repo's target machines (Plasma +
# NVIDIA/CachyOS, WebKitGTK 2.52.6) the webview aborts or renders a blank white
# window regardless of backend/sandbox/DMA-BUF settings. The CLI/TUI provides
# the same gateway and model-switching functionality, so we use that.
#
# Building it here also means magpie's self-updater is bypassed: update by
# bumping `version`/`src` and rebuilding, not with `magpie update`.
{ lib
, buildGoModule
, fetchFromGitHub
, ...
}:

buildGoModule rec {
  pname = "magpie";
  version = "0.1.3383";

  src = fetchFromGitHub {
    owner = "yetone";
    repo = "magpie";
    rev = "9dd7aabca8af76c9467039979076e58d59d3f03b"; # v0.1.3383
    # fetchzip recursive hash of the unpacked source tree (fetchFromGitHub's
    # default for public repos); not the hash of the .tar.gz bytes.
    hash = "sha256-wJWgFaNKqXXVnuKMYwcizFxYM8TQ3o0LELTkUhYZI58=";
  };

  # SRI hash of the vendored dependencies (the recursive output of `go mod
  # vendor`, computed by buildGoModule) - not the hash of go.sum.
  vendorHash = "sha256-9x4oBEHBN1gbREjzwLrPKjwlCq3847nLjP5QHBFEy4E=";

  # Terminal-only build: no cgo, no WebKit/GTK. Cross-compiles cleanly and
  # avoids the broken WebKit rendering path on NVIDIA/Plasma/Wayland.
  env.CGO_ENABLED = "0";
  tags = [ "nogui" ];

  # Upstream's tests shell out to hardcoded /bin/cat, /bin/mkdir and fetch
  # release URLs, so they cannot run in the build sandbox. The build itself is
  # unaffected.
  doCheck = false;

  # Upstream LDFLAGS; buildGoModule already adds -trimpath and -buildid=.
  ldflags = [
    "-s"
    "-w"
    "-X"
    "main.version=${version}"
  ];

  meta = with lib; {
    description = "One place to pick every AI agent's model (TUI/CLI, GUI disabled)";
    homepage = "https://usemagpie.ai";
    license = licenses.mit;
    mainProgram = "magpie";
    platforms = platforms.linux;
  };
}
