{ config, lib, pkgs, ... }:

with lib;

let
  # Daily schedule for sven: allowed 06:00-22:00 (school hours are
  # unrestricted because sven is at school anyway). Seconds since midnight.
  dailyStart = 6 * 60 * 60;
  dailyEnd = 22 * 60 * 60;

  # Kid-safe flatpak app IDs sven may run. Malcontent only enforces app
  # filtering for flatpak apps (native binaries are covered by AppArmor).
  allowlistApps = [
    "org.gnome.Calculator"
    "org.gnome.Maps"
    "org.gnome.Books"
    "org.gnome.Notes"
    "org.gnome.Cheese"
    "org.gnome.Clocks"
    "org.gnome.Logs"
    "org.gnome.Music"
    "org.gnome.Epiphany"
    "org.gnome.Totem"
    "org.videolan.VLC"
    "org.kde.okular"
    "org.kde.gwenview"
    "org.kde.dolphin"
    "org.kde.kalk"
    "org.gimp.GIMP"
    "org.kde.krita"
    "org.libreoffice.LibreOffice"
    "org.mozilla.firefox"
    "org.gnome.SystemMonitor"
  ];

  # OARS content-ratings filter: allow up to 'moderate' for most sections
  # (teen-appropriate), keep sexual content, narcotics and gambling at 'none'
  # and alcohol/tobacco at 'mild'.
  oarsFilter = {
    "violence-realistic" = "moderate";
    "violence-bloodshed" = "moderate";
    "violence-sexual" = "none";
    "violence-cartoon" = "intense";
    "violence-fantasy" = "moderate";
    "drugs-alcohol" = "mild";
    "drugs-narcotics" = "none";
    "drugs-tobacco" = "mild";
    "sex-nudity" = "mild";
    "sex-themes" = "mild";
    "language-profanity" = "moderate";
    "language-humor" = "intense";
    "language-discrimination" = "mild";
    "social-chat" = "moderate";
    "social-audio" = "moderate";
    "social-info" = "moderate";
    "social-contacts" = "moderate";
    "money-purchasing" = "moderate";
    "money-gambling" = "none";
  };

  # GVariant text-format values (g_variant_print output) as stored by
  # accountsservice in the per-user keyfile.
  sessionLimitsSection = ''
    [com.endlessm.ParentalControls.SessionLimits]
    LimitType=1
    DailySchedule=(${toString dailyStart}, ${toString dailyEnd})
  '';

  appFilterSection = ''
    [com.endlessm.ParentalControls.AppFilter]
    AppFilter=(true, [${concatMapStringsSep ", " (app: "'${app}'") allowlistApps}])
    OarsFilter=('oars-1.1', {${concatStringsSep ", " (mapAttrsToList (section: value: "'${section}': '${value}'") oarsFilter)}})
    AllowUserInstallation=false
    AllowSystemInstallation=false
  '';
in
{
  config = {
    services.malcontent.enable = mkDefault true;

    # Write sven's parental-control restrictions to the accountsservice user
    # keyfile. The daemon reads this on startup and reloads when it changes.
    # Merge into the existing file so accountsservice's per-user state
    # (e.g. the remembered Session) is preserved across boots.
    system.activationScripts.malcontent-sven = mkIf (config.users.users ? sven) {
      text = ''
        install -d -m 0700 -o root -g root /var/lib/AccountsService/users
        cat > /var/lib/AccountsService/users/.sven-malcontent <<'EOF'
        [User]
        SystemAccount=false

        ${sessionLimitsSection}
        ${appFilterSection}
        EOF
        ${pkgs.python3}/bin/python3 - <<'EOF'
        import configparser, os

        src = "/var/lib/AccountsService/users/.sven-malcontent"
        dst = "/var/lib/AccountsService/users/sven"

        cfg = configparser.ConfigParser(interpolation=None)
        cfg.optionxform = str  # preserve key case
        if os.path.exists(dst):
            cfg.read(dst)

        extra = configparser.ConfigParser(interpolation=None)
        extra.optionxform = str
        extra.read(src)

        for name in extra.sections():
            if not cfg.has_section(name):
                cfg.add_section(name)
            for key, value in extra.items(name):
                cfg.set(name, key, value)

        with open(dst, "w") as f:
            cfg.write(f, space_around_delimiters=False)

        os.unlink(src)
        EOF
        chmod 0600 /var/lib/AccountsService/users/sven
        chown root:root /var/lib/AccountsService/users/sven
      '';
    };

    # Enforce session time limits at login for sven via pam_malcontent.
    security.pam.services.login.rules.account.malcontent = mkIf (config.users.users ? sven) {
      control = "required";
      modulePath = "${pkgs.malcontent.pam}/lib/security/pam_malcontent.so";
      # Run before the other account rules.
      order = config.security.pam.services.login.rules.account.unix.order - 10;
    };
  };
}
