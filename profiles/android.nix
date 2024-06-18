{ config, lib, pkgs, ... }:

with lib;
{
  programs.adb.enable = true;
  environment.systemPackages = with pkgs; [
    android-studio
    android-tools
    cargo-ndk # Cargo extension for building Android NDK projects.
    gradle
    gradle-completion # Gradle tab completion for bash and zsh.
  ];
}
