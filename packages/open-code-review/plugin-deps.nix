# The official OpenCode integration of Open Code Review
# (plugins/open-code-review/opencode in alibaba/open-code-review, pinned to
# the same release as the ocr CLI in ./default.nix): a single TypeScript file
# that registers native opencode tools — `ocr_review` / `ocr_health` — plus
# the /ocr-review and /ocr-health slash commands. The dual-form file serves
# opencode 1.x (server entrypoint) and 2.x (id + setup entrypoint); this repo
# runs opencode v2 (packages/opencode2).
#
# The plugin imports its SDKs at runtime and opencode does not bundle them
# (unresolved imports only show up as "Cannot find package ..." in the server
# log), so this derivation also builds the node_modules tree that
# users/opencode.nix links into ~/.config/opencode. OpenCode 2.x needs both
# @opencode-ai/plugin (1.x SDK, imported as types) and @opencode/plugin (the
# 2.x setup API) — see the plugin README. The locked versions live in
# ./plugin/package-lock.json, generated 2026-10-21 with
# `npm install --package-lock-only` from the dist-tags of that date.
#
# Prerequisites at runtime: the `ocr` binary on PATH (./default.nix, via
# home.packages) and `ocr config provider` / `ocr config model` run once, or
# delegation mode (no LLM config needed).
{ lib
, buildNpmPackage
, fetchurl
}:

let
  version = "1.13.3";

  # Plugin file pinned to the same release as the CLI so tools and CLI stay
  # in sync (hash via `nix store prefetch-file`).
  pluginFile = fetchurl {
    url = "https://raw.githubusercontent.com/alibaba/open-code-review/v${version}/plugins/open-code-review/opencode/open-code-review.ts";
    hash = "sha256-iEO2NrQZsKYq9DYpxnwRJIKFzRSr+DQ9oMGE1P1W+V4=";
  };
in
buildNpmPackage {
  pname = "opencode-ocr-plugin";
  inherit version;

  src = ./plugin;

  npmDepsHash = "sha256-fzGPVCetheVqj5MSzXjw7yKX9F9KdxqKZAMYJZJqMrQ=";

  dontNpmBuild = true;

  # The default npmInstallHook publishes the host package itself; we only
  # want the resolved node_modules tree and the plugin file.
  installPhase = ''
    runHook preInstall
    mkdir -p $out/plugin
    cp ${pluginFile} $out/plugin/open-code-review.ts
    cp -r node_modules $out/node_modules
    runHook postInstall
  '';

  meta = with lib; {
    description = "Open Code Review plugin for opencode (ocr_review/ocr_health tools) + its SDK node_modules";
    homepage = "https://open-codereview.ai";
    license = licenses.asl20;
    platforms = platforms.linux;
  };
}
