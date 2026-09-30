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
  version = "0.1.384";

  src = fetchFromGitHub {
    owner = "yetone";
    repo = "magpie";
    rev = "12d79dd9f509f2128b0bf725c97a3c50e0748aa2"; # v0.1.384
    hash = "sha256-6sBawN29VdL+EWpXk0YM54K4NaboZB0Lw4Ar2dRZD1A=";
  };

  vendorHash = "sha256-7I/9ybvVtYGHsx1xvRvoy+xKfAC2nGjVW1DuU49caaY=";

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
