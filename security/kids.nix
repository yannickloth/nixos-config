{ config, lib, ... }:

with lib;

{
  # Invariants and privilege restrictions for the kids' accounts (sven, aaron).
  # Imported for all hosts via roles/base.nix.

  # The kids must never gain admin (wheel/sudo). These assertions fail the
  # build/switch if they ever get added to the wheel group.
  assertions =
    (optional (config.users.users ? sven) {
      assertion = !(elem "wheel" (config.users.users.sven.extraGroups or [ ]));
      message = "sven must never be a member of the wheel group";
    })
    ++ (optional (config.users.users ? aaron) {
      assertion = !(elem "wheel" (config.users.users.aaron.extraGroups or [ ]));
      message = "aaron must never be a member of the wheel group";
    });

  # Kids cannot change network settings (DNS, proxy, IP, hostname) or create
  # hotspots — otherwise they could bypass the family DNS filter. Connecting to
  # already-configured networks stays allowed (org.freedesktop.NetworkManager.network-control).
  security.polkit.extraConfig = ''
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
