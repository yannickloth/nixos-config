{ config, lib, pkgs, ... }:

with lib;
{
  programs.java = {
    enable = true; # Install and setup the Java development kit. This adds JAVA_HOME to the global environment, by sourcing the jdk’s setup-hook on shell init.
    package = pkgs.jdk22; # The jdk package to use.
    binfmt = true; # Whether to enable binfmt to execute java jar’s and classes.
  };
}
