# Natural (inverse) scrolling for all mice and touchpads.
#
# KDE Plasma reads ~/.config/kcminputrc at login and applies the input settings
# to every pointer/touchpad device. The NaturalScroll.java script merges the
# natural-scroll keys into the existing file (preserving the user's other
# settings) via a Java 25 compact source file.
{ config, lib, pkgs, ... }:

{
  # Explicit dependency: the setNaturalScroll activation runs
  # ${pkgs.jdk25}/bin/java. home.packages keeps the JDK in the home-manager
  # generation closure, so the activation works even if apps/java.nix changes.
  home.packages = [ pkgs.jdk25 ];

  home.activation.setNaturalScroll = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    ${pkgs.jdk25}/bin/java ${./NaturalScroll.java} || true
  '';
}
