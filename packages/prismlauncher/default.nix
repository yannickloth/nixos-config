# Prism Launcher (free, open source launcher for Minecraft) with the family's
# shared setup: the extra binaries some mods need, controller and GameMode
# support, and the Java runtimes offered to instances.
#
# One definition, two deployments:
#   * NixOS hosts install it system-wide (games/games.nix, in
#     environment.systemPackages), so every user on the host gets it;
#   * the standalone CachyOS deployment (users/flake.nix) has no NixOS
#     modules, so users/common-hm.nix installs it per-user there instead,
#     gated on commonHm.isCachyOS.
# Keeping the override here means both paths offer the same runtimes and
# launcher features.
#
# callPackage resolves every argument below from the caller's pkgs, so the
# stable (users/flake.nix) and unstable (root flake.nix) pins each use their
# own build of the same version.
{
  prismlauncher,
  ffmpeg,
  optifine,
  graalvmPackages,
  jdk,
  jdk25,
}:

prismlauncher.override {
  # Binary required by some mods.
  additionalPrograms = [
    ffmpeg
    optifine # performance/render mod; nixpkgs pins the Minecraft version
  ];
  controllerSupport = true; # default: stdenv.hostPlatform.isLinux
  gamemodeSupport = true; # default: stdenv.hostPlatform.isLinux
  # Java runtimes available to Prism Launcher.
  jdks = [
    graalvmPackages.graalvm-ce
    jdk
    jdk25
  ];
}
