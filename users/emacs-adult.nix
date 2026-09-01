# Shared GNU Emacs setup for adults (nicky, aeiuno).
#
# Uses a prebuilt GUI Emacs (pkgs.emacs-gtk) pulled from the binary cache,
# so nothing needs to be compiled. All Elisp packages are also provided by
# Nix (programs.emacs.extraPackages), so the config performs no package
# fetching or compilation at runtime. Language servers (eglot) are provided
# via home.packages so they end up in the user's PATH.
{ pkgs, ... }:

{
  programs.emacs = {
    enable = true;
    package = pkgs.emacs-gtk;
    extraPackages = epkgs: with epkgs; [
      auctex
      csharp-mode
      consult
      corfu
      go-mode
      haskell-mode
      marginalia
      markdown-mode
      magit
      nix-mode
      orderless
      purescript-mode
      rust-mode
      typst-ts-mode
      typescript-mode
      vertico
      which-key
    ];
    extraConfig = builtins.readFile ./adult-emacs-config.el;
  };

  # Language servers used by eglot. Each server is matched to a major mode in
  # adult-emacs-config.el.
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
