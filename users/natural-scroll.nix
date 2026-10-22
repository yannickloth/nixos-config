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
    # Natural scrolling is cosmetic: never let it abort the rest of the
    # activation (the snippet runs inline under `set -eu`). The subshell keeps
    # `exit` local, `set +e` keeps a failing java from killing the script, and
    # a trap guarantees the temp dir is removed on any early exit.
    (
      set +e

      # `java File.java` (JEP 458) only works when the file name ends in .java
      # AND the base name is a valid Java identifier, but nix store paths are
      # hash-prefixed and extension-less. Copy to a temp dir under a valid
      # class-style name, run, clean up.
      NS_DIR=$(${pkgs.coreutils}/bin/mktemp -d 2>/dev/null)
      if [ -z "$NS_DIR" ]; then
        echo "setNaturalScroll: cannot create a temp dir; skipping" >&2
        exit 0
      fi
      trap '${pkgs.coreutils}/bin/rm -rf "$NS_DIR"' EXIT

      $DRY_RUN_CMD ${pkgs.coreutils}/bin/cp ${./NaturalScroll.java} "$NS_DIR/NaturalScroll.java"
      $DRY_RUN_CMD ${pkgs.jdk25}/bin/java "$NS_DIR/NaturalScroll.java"
      _ns_rc=$?
      if [ "$_ns_rc" -ne 0 ]; then
        echo "setNaturalScroll: NaturalScroll.java failed (exit $_ns_rc); continuing" >&2
      fi
    ) || true
  '';
}
