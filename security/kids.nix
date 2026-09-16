{ config, lib, ... }:

with lib;

{
  # Invariants and privilege restrictions for the kids' accounts (sven, aaron).
  # Imported for all hosts via roles/base.nix.

  # The kids must never gain admin (wheel/sudo). These assertions fail the
  # build/switch if they ever get added to the wheel group, whether via their
  # own extraGroups or the wheel group's members list.
  assertions =
    (optional (config.users.users ? sven) {
      assertion = !(elem "wheel" (config.users.users.sven.extraGroups or [ ]))
      && !(elem "sven" ((config.users.groups.wheel or { }).members or [ ]));
      message = "sven must never be a member of the wheel group";
    })
    ++ (optional (config.users.users ? aaron) {
      assertion = !(elem "wheel" (config.users.users.aaron.extraGroups or [ ]))
      && !(elem "aaron" ((config.users.groups.wheel or { }).members or [ ]));
      message = "aaron must never be a member of the wheel group";
    });

  # polkit must actually run for the rule below to be enforced.
  security.polkit.enable = mkDefault true;

  # Kids cannot change network settings (DNS, proxy, IP, hostname) or create
  # hotspots — otherwise they could bypass the family DNS filter. Connecting to
  # already-configured networks stays allowed
  # (org.freedesktop.NetworkManager.network-control), as does toggling wifi
  # (enable-disable-wifi).
  #
  # polkit evaluates rules in order and the FIRST rule that returns a value
  # wins. This deny must therefore run before the NixOS networkmanager rule that
  # grants the networkmanager group every org.freedesktop.NetworkManager.*
  # action (both rules live in the same /etc/polkit-1/rules.d/10-nixos.rules);
  # mkBefore pins that order instead of relying on merge order.
  security.polkit.extraConfig = mkBefore ''
    polkit.addRule(function (action, subject) {
      if (subject.user == "sven" || subject.user == "aaron") {
        if (action.id.indexOf("org.freedesktop.NetworkManager.settings.modify") === 0 ||
            action.id.indexOf("org.freedesktop.NetworkManager.wifi.share") === 0) {
          return polkit.Result.NO;
        }
      }
    });
  '';
}
