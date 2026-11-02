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
  version = "0.1.2359";

  src = fetchFromGitHub {
    owner = "yetone";
    repo = "magpie";
    rev = "4d6bd346ce371ba859c477cc8357ce51d8144f03"; # v0.1.2359
    hash = "sha256-hlM9LXDwTwXGoPbDlXuLKFeLajtWKbIyKqNOzp6PPL0=";
  };

  # go.mod/go.sum moved again by v0.1.2359 (the earlier v0.1.1294 -> v0.1.1554
  # span left them alone).
  vendorHash = "sha256-CSFUYQB28DBs0oQSObJEqu07+b7T7DKxINQVu+lHNUw=";

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
