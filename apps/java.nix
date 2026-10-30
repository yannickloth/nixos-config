{ config, lib, pkgs, ... }:

with lib;
{
  programs.java = {
    enable = true; # Install and setup the Java development kit. This adds JAVA_HOME to the global environment, by sourcing the jdk’s setup-hook on shell init.
    # jdk25 IS the newest nixpkgs ships (checked 2026-10-20 against
    # nixpkgs-unstable fp 59e6964 and upstream: only 8, 11, 17, 21, 25 exist;
    # 23 and 24 throw "removed, reached end of life"). `pkgs.jdk` is the
    # default, currently 21.0.12 LTS - switching to it would be a downgrade, and
    # the repo's compact Java sources (users/NaturalScroll.java,
    # services/MalcontentMerge.java) are written for 25.
    # Nothing named jdk-latest/jdk_latest exists. Revisit when nixpkgs adds 26.
    package = pkgs.jdk25; # The jdk package to use.
    binfmt = true; # Whether to enable binfmt to execute java jar’s and classes.
  };
}
