{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.apps.flatpak;
in
{
  # Declarative flatpak app installation. Apps installed here system-wide are
  # the ones malcontent's per-user allowlist can actually gate for sven/aaron
  # (malcontent only filters flatpak apps). Keep browsers in Nix so the Firefox
  # kid policies (users/kid-firefox-policies.nix) keep applying.
  #
  # Install runs at boot (needs network). `flatpak install --or-update` is a
  # no-op once the ref is already present.
  options.apps.flatpak = {
    enable = mkEnableOption "declarative flatpak app installation (malcontent-gated apps)";

    apps = mkOption {
      type = types.listOf types.str;
      default = [ ];
      example = [ "app/org.videolan.VLC/x86_64/stable" ];
      description = "Flatpak app refs to install system-wide. Keep in sync with the malcontent allowlist (services/malcontent.nix).";
    };

    overrides = mkOption {
      type = types.attrsOf (types.listOf types.str);
      default = { };
      example = { "org.libreoffice.LibreOffice" = [ "--filesystem=/filedrop" ]; };
      description = "Per-app extra `flatpak override --system` CLI arguments (e.g. filesystem grants for shared folders like /filedrop).";
    };
  };

  config = mkIf cfg.enable {
    services.flatpak.enable = mkDefault true;

    systemd.services.flatpak-install = {
      description = "Install declared flatpak apps";
      wantedBy = [ "multi-user.target" ];
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      path = [ pkgs.flatpak ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        ${pkgs.flatpak}/bin/flatpak remote-add --if-not-exists --system flathub https://flathub.org/repo/flathub.flatpakrepo
        ${concatStringsSep "\n" (map (app: ''
          echo "flatpak: ensuring ${app}"
          ${pkgs.flatpak}/bin/flatpak install --system --noninteractive --or-update flathub ${app} || true
        '') cfg.apps)}
        ${concatStringsSep "\n" (mapAttrsToList (app: args: ''
          echo "flatpak: override ${app} ${toString args}"
          ${pkgs.flatpak}/bin/flatpak override --system ${toString args} ${app} || true
        '') cfg.overrides)}
      '';
    };
  };
}
