# Shared GNU Emacs setup for the kids (aaron, sven).
#
# Uses a prebuilt GUI Emacs (pkgs.emacs-gtk) pulled from the binary cache,
# so nothing needs to be compiled. Just the minimal extra package that helps
# kids learn the keybindings.
{ pkgs, ... }:

{
  programs.emacs = {
    enable = true;
    package = pkgs.emacs-gtk;
    extraPackages = epkgs: with epkgs; [
      which-key
    ];
    extraConfig = builtins.readFile ./kid-emacs-config.el;
  };
}
