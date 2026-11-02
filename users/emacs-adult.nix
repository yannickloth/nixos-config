# Shared GNU Emacs setup for adults (nicky, aeiuno).
#
# The adults use the same shared minimal Emacs as the kids
# (users/emacs.nix: prebuilt emacs-gtk + which-key + emacs-config.el),
# imported below so the two can't drift apart.
# The previous heavy setup (auctex, magit, vertico, ...) was dropped:
# nixpkgs 26.05's default Emacs (30.2) is built with native compilation, so
# every entry in extraPackages gets natively recompiled at build time, and
# those per-Emacs wrappers are not in cache.nixos.org - every `nix flake
# update` triggered a slow local build (auctex was the worst of it). The old
# rich config is kept in adult-emacs-config.el, no longer wired up.
#
# Language servers are still provided via home.packages so they end up in the
# user's PATH (usable by other LSP clients; eglot is not configured in the
# kid-style init file).
{ pkgs, ... }:

{
  # The shared Emacs configuration (same for kids and adults).
  imports = [ ../emacs.nix ];

  # Language servers, installed on the PATH for LSP clients.
  home.packages = with pkgs; [
    clang-tools # clangd for C/C++
    csharp-ls # C# (OmniSharp)
    gopls # Go
    haskell-language-server # Haskell
    jdt-language-server # Java
    marksman # Markdown
    rust-analyzer # Rust
    texlab # LaTeX
    tinymist # Typst
    typescript-language-server # TypeScript / JavaScript
    (callPackage ../packages/tools/purescript-language-server/default.nix { }) # PureScript
  ];
}
