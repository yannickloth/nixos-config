# Declarative per-user flatpak app installation.
#
# Apps are installed per-user (flatpak --user) instead of system-wide. Malcontent
# gates sven/aaron by flatpak app id and filters per-user apps exactly like
# system ones, so the kids' allowlist (services/malcontent.nix) still applies.
#
# Per-user installs also let nicky and aeiuno run only the apps they don't
# already have from Nixpkgs (apps.flatpak.adultApps), avoiding two copies of
# the same app (one Nixpkgs, one flatpak).
#
# Install runs in each user's session (needs network). `flatpak install
# --or-update` is a no-op once the ref is already present.
#
# Keep apps.flatpak.apps in sync with the malcontent allowlist
# (services/malcontent.nix). Browsers stay in Nix so the Firefox kid policies
# (users/kid-firefox-policies.nix) keep applying.
{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.apps.flatpak;

  # "app/org.kde.krita/x86_64/stable" -> "org.kde.krita"
  # builtins.split keeps empty lists at the separators, so filter for the
  # string parts first. A malformed ref (fewer than two parts) must fail with a
  # clear message instead of throwing an opaque elemAt error.
  appIdOf =
    ref:
    let
      parts = builtins.filter builtins.isString (builtins.split "/" ref);
    in
    if builtins.length parts >= 2 then
      builtins.elemAt parts 1
    else
      throw "apps.flatpak: malformed app ref '${ref}' (expected app/<id>/<arch>/<branch>)";
in
{
  options.apps.flatpak = {
    enable = mkEnableOption "declarative per-user flatpak app installation";

    apps = mkOption {
      type = types.listOf types.str;
      default = [ ];
      example = [ "app/org.videolan.VLC/x86_64/stable" ];
      description = "Flatpak app refs installed per-user for the kids (sven, aaron). Kept in sync with the malcontent allowlist (services/malcontent.nix).";
    };

    adultApps = mkOption {
      type = types.listOf types.str;
      default = [ ];
      example = [ "app/org.gnome.Calculator/x86_64/stable" ];
      description = "Flatpak app refs installed per-user for the adults (nicky, aeiuno). Must be disjoint from their Nixpkgs packages so no app is installed twice.";
    };

    overrides = mkOption {
      type = types.attrsOf (types.listOf types.str);
      default = { };
      example = { "org.libreoffice.LibreOffice" = [ "--filesystem=/filedrop" ]; };
      description = "Per-app extra `flatpak override --user` CLI arguments (e.g. filesystem grants for shared folders like /filedrop). Applied for every user who has the app.";
    };
  };

  config = mkIf cfg.enable {
    services.flatpak.enable = mkDefault true;

    # Per-user flatpak installer. Evaluated per home-manager user; apps land in
    # each user's own ~/.local/share/flatpak and only for the refs on their
    # list (kids get the full malcontent-gated set, adults only the apps they
    # don't also get from Nixpkgs).
    home-manager.sharedModules = [
      (
        { config, pkgs, lib, ... }:
        let
          userApps = {
            nicky = cfg.adultApps;
            aeiuno = cfg.adultApps;
            sven = cfg.apps;
            aaron = cfg.apps;
          }.${config.home.username} or [ ];
          userOverrides =
            let
              ids = map appIdOf userApps;
            in
            mapAttrsToList
              (id: args: {
                inherit id args;
              })
              (filterAttrs (id: _: builtins.elem id ids) cfg.overrides);
        in
        {
          config = lib.mkIf (userApps != [ ]) {
            systemd.user.services.flatpak-install = {
              Unit = {
                Description = "Install per-user flatpak apps for ${config.home.username}";
                # No After=network-online.target here: that target lives in the
                # system manager, so ordering on it from a *user* unit is inert.
                # The installer retries instead (and runs again next login if it
                # gave up).
              };
              Install.WantedBy = [ "default.target" ];
              Service = {
                Type = "oneshot";
                RemainAfterExit = true;
                ExecStart = pkgs.writeShellScript "flatpak-install-user" ''
                  set -eu
                  FLATPAK="${pkgs.flatpak}/bin/flatpak"
                  retry() {
                    local i=0
                    until "$@"; do
                      i=$((i + 1))
                      if [ "$i" -ge 3 ]; then
                        echo "flatpak: giving up after $i attempts: $*" >&2
                        return 1
                      fi
                      sleep 10
                    done
                  }
                  retry "$FLATPAK" remote-add --user --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
                  ${concatStringsSep "\n" (map (app: ''
                    echo "flatpak: ensuring ${app} for ${config.home.username}"
                    retry "$FLATPAK" install --user --noninteractive --or-update flathub ${escapeShellArg app}
                  '') userApps)}
                  ${concatStringsSep "\n" (map (o: ''
                    echo "flatpak: override ${o.id}"
                    retry "$FLATPAK" override --user ${escapeShellArgs o.args} ${escapeShellArg o.id}
                  '') userOverrides)}
                '';
              };
            };
          };
        }
      )
    ];
  };
}
