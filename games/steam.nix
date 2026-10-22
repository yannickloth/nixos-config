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
    # The module's openFirewall flags accept these ports on *every* interface,
    # which on a roaming laptop exposes the Remote Play / game-transfer
    # listeners on hotel Wi-Fi. The scoped rules below replace them.
    dedicatedServer.openFirewall = false;
    enable = true;
    localNetworkGameTransfers.openFirewall = false;
    remotePlay.openFirewall = false;
  };

  # Steam ports (from nixpkgs' programs/steam.nix: dedicated 27015, Remote Play
  # TCP 27036-27037 + UDP 27031-27036 + 10400-10401, transfers 27040),
  # reachable from private ranges only. Needs the nftables backend.
  assertions = [
    {
      assertion = config.networking.nftables.enable;
      message = "games/steam.nix: the scoped Steam ports require networking.nftables.enable";
    }
  ];

  networking.firewall.extraInputRules = ''
    ip saddr { 192.168.0.0/16, 10.0.0.0/8, 172.16.0.0/12, 100.64.0.0/10 } tcp dport { 27015, 27036, 27037, 27040 } accept
    ip saddr { 192.168.0.0/16, 10.0.0.0/8, 172.16.0.0/12, 100.64.0.0/10 } udp dport { 10400, 10401, 27015, 27031-27036 } accept
    ip6 saddr { fc00::/7, fe80::/10 } tcp dport { 27015, 27036, 27037, 27040 } accept
    ip6 saddr { fc00::/7, fe80::/10 } udp dport { 10400, 10401, 27015, 27031-27036 } accept
  '';
}
