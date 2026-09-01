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
    # `java File.java` (JEP 458) only works when the file name ends in .java
    # AND the base name is a valid Java identifier, but nix store paths are
    # hash-prefixed and extension-less. Copy to a temp dir under a valid
    # class-style name, run, clean up.
    NS_DIR=$(${pkgs.coreutils}/bin/mktemp -d)
    ${pkgs.coreutils}/bin/cp ${./NaturalScroll.java} "$NS_DIR/NaturalScroll.java"
    ${pkgs.jdk25}/bin/java "$NS_DIR/NaturalScroll.java"
    _ns_rc=$?
    ${pkgs.coreutils}/bin/rm -rf "$NS_DIR"
    # Only fail the activation when Java actually fails. `exit $_ns_rc`
    # unconditionally terminates the whole hm activate script (even on
    # success), silently skipping every later activation entry such as
    # setupOpenCodeKeys/setupTresorit.
    if [ "$_ns_rc" -ne 0 ]; then
      echo "setNaturalScroll: NaturalScroll.java failed (exit $_ns_rc)" >&2
      exit 1
    fi
  '';
}
