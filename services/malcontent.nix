{ config, lib, pkgs, ... }:

with lib;

let
  # Daily schedule for sven and aaron: allowed 06:00-22:00 (school hours are
  # unrestricted because they are at school anyway). Seconds since midnight.
  dailyStart = 6 * 60 * 60;
  dailyEnd = 22 * 60 * 60;

  # Lock time as HH:MM, derived from the daily schedule above.
  lockAt =
    let
      h = dailyEnd / 3600;
      m = (dailyEnd - h * 3600) / 60;
      mm = if m == 0 then "00" else toString m;
    in
    "${toString h}:${mm}";

  # Kid-safe flatpak app IDs sven and aaron may run. Malcontent only enforces app
  # filtering for flatpak apps. Native binaries are gated by per-user home-manager
  # package installation (the AppArmor LSM is enabled but defines no per-user
  # native-binary profiles in this repo).
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
    "org.gnome.Geary"
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

    # Explicit dependency: the malcontent-kids activation script below runs
    # ${pkgs.python3}/bin/python3. system.activationScripts only guarantee a
    # fixed tool set, so declare python3 here to keep it in the system closure
    # even if roles/base.nix stops shipping it.
    environment.systemPackages = [ pkgs.python3 ];

    # Write sven's and aaron's parental-control restrictions to the accountsservice
    # per-user keyfile. The daemon reads this on startup and reloads when it changes.
    # Merge into the existing file so accountsservice's per-user state
    # (e.g. the remembered Session) is preserved across boots.
    system.activationScripts.malcontent-kids = mkIf (config.users.users ? sven || config.users.users ? aaron) {
      text =
        let
          mkUser = user: ''
            install -d -m 0700 -o root -g root /var/lib/AccountsService/users
            cat > /var/lib/AccountsService/users/.${user}-malcontent <<'EOF'
            [User]
            SystemAccount=false

            ${sessionLimitsSection}
            ${appFilterSection}
            EOF
            ${pkgs.python3}/bin/python3 - <<'EOF'
            import configparser, os

            src = "/var/lib/AccountsService/users/.${user}-malcontent"
            dst = "/var/lib/AccountsService/users/${user}"

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
            chmod 0600 /var/lib/AccountsService/users/${user}
            chown root:root /var/lib/AccountsService/users/${user}
          '';
          users = [ ] ++ (if config.users.users ? sven then [ "sven" ] else [ ]) ++ (if config.users.users ? aaron then [ "aaron" ] else [ ]);
        in
        lib.concatStringsSep "\n" (map mkUser users);
    };

    # Enforce session time limits at login for sven/aaron via pam_malcontent.
    security.pam.services.login.rules.account.malcontent = mkIf (config.users.users ? sven || config.users.users ? aaron) {
      control = "required";
      modulePath = "${pkgs.malcontent.pam}/lib/security/pam_malcontent.so";
      # Run before the other account rules.
      order = config.security.pam.services.login.rules.account.unix.order - 10;
    };

    # Must-click (modal kdialog) warnings 30/15/5 minutes before the daily lock,
    # running in the kid's graphical session.
    home-manager.sharedModules = [
      ({ config, pkgs, ... }: {
        config = mkIf (config.home.username == "sven" || config.home.username == "aaron") {
          home.packages = [ pkgs.kdePackages.kdialog ];
          # Lock the screen after idle (10 min on AC, 5 min on battery) so a kid
          # can't wander off with an unlocked session.
          home.file = {
            ".config/kscreenlockerrc".text = ''
              [Daemon]
              Autolock=true
              LockOnResume=false
            '';
            ".config/powermanagementprofilesrc".text = ''
              [AC][DPMSControl]
              idleTime=600
              lockBeforeTurnOff=10
              [Battery][DPMSControl]
              idleTime=300
              lockBeforeTurnOff=10
            '';
          };
          systemd.user.services.session-limit-reminder = {
            Unit.Description = "Warn before the daily session lock";
            Install.WantedBy = [ "default.target" ];
            Service = {
              Type = "simple";
              Restart = "always";
              RestartSec = "30";
              ExecStart = "${pkgs.bash}/bin/bash ${./session-limit-reminder.sh} ${lockAt} kdialog 1800,900,300";
            };
          };
        };
      })
    ];
  };
}
