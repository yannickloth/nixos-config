{ config, lib, pkgs, ... }:

with lib;
{
  # Every Linux user gets their own Steam library in ~/.local/share/Steam.
  #
  # Sharing a single Steam library between Linux users does not work for
  # Proton games: Wine deliberately refuses to use a prefix
  # (steamapps/compatdata/<appid>/pfx) that is not owned by the running user,
  # and Steam puts the prefix in the library where the game is installed. See
  # ValveSoftware/Proton#4820 (open since 2021). Reported as "wine: '...' is
  # not owned by you"; there is no supported way to redirect compatdata per
  # user, and symlink/bind-mount workarounds break on Steam updates.
  #
  # So instead of sharing the library, each account installs the games it
  # plays and btrfs block-level deduplication (roles/bees.nix) collapses the
  # duplicate game data back to one physical copy. The legacy /steamlib
  # subvolume is no longer a Steam library; it can be deleted once every
  # account has reinstalled the games it wants.
  programs.steam = {
    dedicatedServer.openFirewall = true; # Open ports in the firewall for Source Dedicated Server
    enable = true;
    localNetworkGameTransfers.openFirewall = true; # Open ports in the firewall for Steam Local Network Game Transfers.
    remotePlay.openFirewall = true; # Open ports in the firewall for Steam Remote Play
  };
}
