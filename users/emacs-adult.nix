# Shared GNU Emacs setup for adults (nicky, aeiuno).
#
# Uses a prebuilt GUI Emacs (pkgs.emacs-gtk) pulled from the binary cache,
# so nothing needs to be compiled. All Elisp packages are also provided by
# Nix (programs.emacs.extraPackages), so the config performs no package
# fetching or compilation at runtime.
{ pkgs, ... }:

{
  programs.emacs = {
    enable = true;
    package = pkgs.emacs-gtk;
    extraPackages = epkgs: with epkgs; [
      consult
      corfu
      marginalia
      markdown-mode
      magit
      nix-mode
      orderless
      typescript-mode
      vertico
      which-key
    ];
    extraConfig = builtins.readFile ./adult-emacs-config.el;
  };
}
