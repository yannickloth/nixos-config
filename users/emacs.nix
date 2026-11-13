# Minimal GNU Emacs setup, shared by everyone: the kids (aaron, sven) import
# it directly, the adults (nicky, aeiuno) via users/emacs-adult.nix.
#
# Uses a prebuilt GUI Emacs (pkgs.emacs-gtk) pulled from the binary cache;
# the single elisp package (which-key) builds in seconds. It is the minimal
# extra package that helps kids learn the keybindings.
{ pkgs, ... }:

{
  programs.emacs = {
    enable = true;
    package = pkgs.emacs-gtk;
    extraPackages = epkgs: with epkgs; [
      which-key
    ];
    extraConfig = builtins.readFile ./emacs-config.el;
  };
}
