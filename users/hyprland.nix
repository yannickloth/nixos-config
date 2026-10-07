# Shared Hyprland (Wayland) session for the family laptops, in the spirit of
# Omarchy (https://github.com/omacom/omarchy): a tiling compositor with
# opinionated, good-looking defaults, a Quickshell bar, and the usual hypr*
# helpers. Pairs with the system-level session in desktop/hyprland.nix.
#
# `hyprland.enable` gives a sane, working Hyprland for any user.
# `hyprland.omarchy` layers the full Omarchy-style experience on top: the
# Walker launcher, notifications (mako), idle/lock (hypridle/hyprlock), a
# wallpaper + matugen theming (hyprpaper), automatic night light (gammastep),
# the clipboard manager and screenshots. The adults (nicky, aeiuno) enable
# both; the kids get the base.
{ config, lib, pkgs, ... }:

let
  cfg = config.hyprland;

  mod = "SUPER";

  # Hyprspace (workspace overview) is a native Hyprland plugin, so it must be
  # built against the exact Hyprland it loads into. On NixOS that is the same
  # nixpkgs Hyprland that provides the session, so it works. On CachyOS the
  # session runs the pacman Hyprland, whose ABI the nixpkgs-built plugin will
  # not match, so the overview is disabled there.
  hasOverview = !config.commonHm.isCachyOS;

  # tesseract with the languages the OCR helper needs. Defined once so both the
  # helper and home.packages use the same build (the bare pkgs.tesseract ships
  # without traineddata).
  tesseract = pkgs.tesseract.override { enableLanguages = [ "eng" "fra" "nld" "deu" ]; };

  # Screenshot / screen-recording helpers. They resolve the configured (synced)
  # XDG folders from the environment ($XDG_PICTURES_DIR / $XDG_VIDEOS_DIR),
  # falling back to `xdg-user-dir`, instead of assuming ~/Pictures; the target
  # folder is created first.
  screenshotOutput = pkgs.writeShellScript "omarchy-screenshot-output" ''
    pics="''${XDG_PICTURES_DIR:-$(${pkgs.xdg-user-dirs}/bin/xdg-user-dir PICTURES)}"
    d="$pics/Screenshots"
    mkdir -p "$d"
    exec ${pkgs.hyprshot}/bin/hyprshot -m output -o "$d"
  '';
  screenshotRegion = pkgs.writeShellScript "omarchy-screenshot-region" ''
    pics="''${XDG_PICTURES_DIR:-$(${pkgs.xdg-user-dirs}/bin/xdg-user-dir PICTURES)}"
    d="$pics/Screenshots"
    mkdir -p "$d"
    ${pkgs.hyprshot}/bin/hyprshot -m region --raw \
      | ${pkgs.satty}/bin/satty --filename - \
          --output-filename "$d/$(date +%Y%m%d-%H%M%S).png"
  '';
  screenrecord = pkgs.writeShellScript "omarchy-screenrecord" ''
    # Toggle: a running wf-recorder is stopped (SIGINT finalises the file).
    if ${pkgs.procps}/bin/pkill -INT wf-recorder 2>/dev/null; then
      exit 0
    fi
    vids="''${XDG_VIDEOS_DIR:-$(${pkgs.xdg-user-dirs}/bin/xdg-user-dir VIDEOS)}"
    mkdir -p "$vids"
    exec ${pkgs.wf-recorder}/bin/wf-recorder -f "$vids/recording-$(date +%Y%m%d-%H%M%S).mp4"
  '';

  # SUPER+K: a searchable keybindings cheatsheet, formatted from `hyprctl binds`.
  keybindings = pkgs.writeShellScript "omarchy-keybindings" ''
    ${pkgs.hyprland}/bin/hyprctl binds -j \
      | ${pkgs.jq}/bin/jq -r '.[] | "\(.modmask)|\(.key)|\(.dispatcher)|\(.arg)"' \
      | while IFS='|' read -r mask key disp arg; do
          m=""
          (( mask & 64 )) && m+="SUPER "
          (( mask & 4 ))  && m+="CTRL "
          (( mask & 8 ))  && m+="ALT "
          (( mask & 1 ))  && m+="SHIFT "
          printf '%-26s %s %s\n' "$m$key" "$disp" "$arg"
        done \
      | ${pkgs.fuzzel}/bin/fuzzel --dmenu --prompt "Keybindings: "
  '';

  # OCR: screenshot a region, run tesseract, copy the text to the clipboard.
  screenocr = pkgs.writeShellScript "omarchy-screenocr" ''
    ${pkgs.grim}/bin/grim -g "$(${pkgs.slurp}/bin/slurp)" - \
      | ${tesseract}/bin/tesseract - - -l eng 2>/dev/null \
      | ${pkgs.wl-clipboard}/bin/wl-copy
    ${pkgs.libnotify}/bin/notify-send "OCR" "Text copied to clipboard"
  '';

  # --- Theming (matugen) ----------------------------------------------------
  # Bundled wallpaper so matugen has something to derive colours from; a user
  # can re-theme any image with `omarchy-theme <image>`. Shipped as a directory
  # with a .png file: matugen infers the format from the extension, and a bare
  # store path has none.
  defaultWallpaper = pkgs.runCommand "omarchy-default-wallpaper" { nativeBuildInputs = [ pkgs.imagemagick ]; } ''
    mkdir -p "$out"
    magick -size 3840x2160 gradient:'#1e1e2e'-'#89b4fa' "$out/wallpaper.png"
  '';

  # Regenerate themes from a wallpaper (default: the bundled one) into
  # colors.json (Quickshell) and hypr-colors.conf (Hyprland). Falls back to a
  # Catppuccin palette if matugen/jq yield nothing, so a bad run never leaves
  # the desktop unstyled.
  theme = pkgs.writeShellScript "omarchy-theme" ''
    set -eu
    wall="''${1:-${defaultWallpaper}/wallpaper.png}"
    dir="''${XDG_CONFIG_HOME:-$HOME/.config}/omarchy"
    mkdir -p "$dir"

    # --source-color-index 0 keeps matugen non-interactive: without it matugen
    # prompts for a colour when stdin/stdout is not a TTY (which it never is
    # during home-manager activation), and the run would fail.
    json="$(${pkgs.matugen}/bin/matugen image "$wall" --json hex --mode dark --source-color-index 0 2>/dev/null || echo '{}')"

    pick() { # pick <key> <default>
      printf '%s' "$json" | ${pkgs.jq}/bin/jq -r --arg k "$1" --arg d "$2" '
        (.colors // .) as $c |
        ($c[$k] // $d) as $v |
        (if ($v | type) == "object" then ($v.dark.color // $v.color // $d) else $v end)
      ' 2>/dev/null || printf '%s' "$2"
    }

    norm() { case "$1" in '#'*) printf '%s' "$1" ;; *) printf '#%s' "$1" ;; esac; }
    bg=$(norm "$(pick background '#1e1e2e')")
    fg=$(norm "$(pick on_background '#cdd6f4')")
    surface=$(norm "$(pick surface_container '#313244')")
    accent=$(norm "$(pick primary '#89b4fa')")
    error=$(norm "$(pick error '#f38ba8')")
    hexff() { printf 'rgba(%sff)' "$(printf '%s' "$1" | ${pkgs.coreutils}/bin/tr -d '#')"; }

    cat > "$dir/colors.json" <<EOF
    {
      "background": "$bg",
      "foreground": "$fg",
      "surface": "$surface",
      "accent": "$accent",
      "error": "$error"
    }
    EOF

    cat > "$dir/hypr-colors.conf" <<EOF
    \$accent = $(hexff "$accent")
    \$inactive = rgba(595959aa)
    EOF

    if ${pkgs.procps}/bin/pgrep -x Hyprland >/dev/null 2>&1; then
      ${pkgs.hyprland}/bin/hyprctl reload >/dev/null 2>&1 || true
    fi
  '';

  # Window/workspace management, modelled on Omarchy's defaults.
  coreBinds = [
    "${mod}, RETURN, exec, ${pkgs.alacritty}/bin/alacritty"
    "${mod}, Q, killactive, "
    "${mod}, W, killactive, "
    "${mod}, F, fullscreen, 0"
    "${mod} CTRL, F, fullscreen, 1"
    "${mod}, T, togglefloating, "
    "${mod}, P, pseudo, "
    "${mod}, J, layoutmsg, togglesplit"
    "${mod}, M, exit, "

    "${mod}, left, movefocus, l"
    "${mod}, right, movefocus, r"
    "${mod}, up, movefocus, u"
    "${mod}, down, movefocus, d"
    "${mod} SHIFT, left, swapwindow, l"
    "${mod} SHIFT, right, swapwindow, r"
    "${mod} SHIFT, up, swapwindow, u"
    "${mod} SHIFT, down, swapwindow, d"

    "${mod} CTRL, left, resizeactive, -100 0"
    "${mod} CTRL, right, resizeactive, 100 0"
    "${mod} CTRL, up, resizeactive, 0 -100"
    "${mod} CTRL, down, resizeactive, 0 100"
    "${mod} ALT, left, resizeactive, -25 0"
    "${mod} ALT, right, resizeactive, 25 0"
    "${mod} ALT, up, resizeactive, 0 -25"
    "${mod} ALT, down, resizeactive, 0 25"

    "${mod}, S, togglespecialworkspace, scratchpad"
    "${mod} SHIFT, S, movetoworkspacesilent, special:scratchpad"
    "${mod}, TAB, workspace, e+1"
    "${mod} SHIFT, TAB, workspace, e-1"
    "${mod} CTRL, TAB, workspace, previous"
  ]
  # SUPER + 1..0 -> switch workspace; SUPER + SHIFT + 1..0 -> move window there.
  ++ (lib.concatMap
    (n: [
      "${mod}, ${toString (lib.mod n 10)}, workspace, ${toString n}"
      "${mod} SHIFT, ${toString (lib.mod n 10)}, movetoworkspace, ${toString n}"
    ])
    (lib.range 1 10));

  # Hardware/media keys (no modifier). With the Omarchy profile these go
  # through swayosd-client so volume/brightness show Omarchy's on-screen
  # display; the base profile uses wpctl/brightnessctl (no OSD).
  mediaBinds =
    if cfg.omarchy then [
      ", XF86AudioRaiseVolume, exec, ${pkgs.swayosd}/bin/swayosd-client --output-volume raise"
      ", XF86AudioLowerVolume, exec, ${pkgs.swayosd}/bin/swayosd-client --output-volume lower"
      ", XF86AudioMute, exec, ${pkgs.swayosd}/bin/swayosd-client --output-volume mute-toggle"
      ", XF86AudioMicMute, exec, ${pkgs.swayosd}/bin/swayosd-client --input-volume mute-toggle"
      ", XF86MonBrightnessUp, exec, ${pkgs.swayosd}/bin/swayosd-client --brightness raise"
      ", XF86MonBrightnessDown, exec, ${pkgs.swayosd}/bin/swayosd-client --brightness lower"
      ", XF86AudioPlay, exec, ${pkgs.playerctl}/bin/playerctl play-pause"
      ", XF86AudioNext, exec, ${pkgs.playerctl}/bin/playerctl next"
      ", XF86AudioPrev, exec, ${pkgs.playerctl}/bin/playerctl previous"
    ] else [
      ", XF86AudioRaiseVolume, exec, ${pkgs.wireplumber}/bin/wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%+"
      ", XF86AudioLowerVolume, exec, ${pkgs.wireplumber}/bin/wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-"
      ", XF86AudioMute, exec, ${pkgs.wireplumber}/bin/wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"
      ", XF86AudioMicMute, exec, ${pkgs.wireplumber}/bin/wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"
      ", XF86AudioPlay, exec, ${pkgs.playerctl}/bin/playerctl play-pause"
      ", XF86AudioNext, exec, ${pkgs.playerctl}/bin/playerctl next"
      ", XF86AudioPrev, exec, ${pkgs.playerctl}/bin/playerctl previous"
      ", XF86MonBrightnessUp, exec, ${pkgs.brightnessctl}/bin/brightnessctl set 5%+"
      ", XF86MonBrightnessDown, exec, ${pkgs.brightnessctl}/bin/brightnessctl set 5%-"
    ];

  # Overview (GNOME Activities equivalent), only where the plugin can load.
  overviewBinds = [
    "${mod}, grave, overview:toggle"
  ];

  # Omarchy extras: launcher, app launchers, screenshots, clipboard, lock,
  # night light. Mirrors Omarchy's default/hypr/bindings/applications.lua plus
  # the utilities. Apps go through xdg-open so they work regardless of which
  # browser/editor a user has.
  omarchyBinds = [
    "${mod}, SPACE, exec, ${pkgs.walker}/bin/walker"
    "${mod} SHIFT, RETURN, exec, xdg-open https://"
    "${mod} SHIFT, B, exec, xdg-open https://"
    "${mod} SHIFT, F, exec, xdg-open ~"
    "${mod} SHIFT, N, exec, xdg-open ."
    ", PRINT, exec, ${screenshotOutput}"
    "${mod}, PRINT, exec, ${pkgs.hyprpicker}/bin/hyprpicker -a"
    "${mod} SHIFT, PRINT, exec, ${screenshotRegion}"
    "${mod} ALT, PRINT, exec, ${screenrecord}"
    "${mod} CTRL, V, exec, ${pkgs.cliphist}/bin/cliphist list | ${pkgs.fuzzel}/bin/fuzzel --dmenu | ${pkgs.cliphist}/bin/cliphist decode | ${pkgs.wl-clipboard}/bin/wl-copy"
    "${mod} CTRL, L, exec, ${pkgs.hyprlock}/bin/hyprlock"
    # Night light: gammastep runs on a schedule; SIGUSR1 toggles it.
    "${mod} CTRL, N, exec, ${pkgs.procps}/bin/pkill -USR1 gammastep"
    # Display arrangement (like Plasma's display settings) and keybindings help.
    "${mod} CTRL, D, exec, ${pkgs.nwg-displays}/bin/nwg-displays"
    "${mod}, K, exec, ${keybindings}"
    # OCR a screen region to the clipboard.
    "${mod} CTRL, PRINT, exec, ${screenocr}"
    # Emoji picker and calculator.
    "${mod} CTRL, E, exec, ${pkgs.rofimoji}/bin/rofimoji --selector fuzzel --clipboard"
    "${mod} CTRL, Q, exec, ${pkgs.qalculate-qt}/bin/qalculate-qt"
    # Notifications / Do Not Disturb, matching Omarchy's SUPER+, binds.
    "${mod}, comma, exec, ${pkgs.mako}/bin/makoctl dismiss"
    "${mod} SHIFT, comma, exec, ${pkgs.mako}/bin/makoctl dismiss --all"
    "${mod} CTRL, comma, exec, ${pkgs.mako}/bin/makoctl mode -t do-not-disturb"
  ];
in
{
  options.hyprland = {
    enable = lib.mkEnableOption "the Hyprland Wayland session and its Omarchy-style base config";
    omarchy = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Layer the full Omarchy-style additions (Walker launcher, mako
        notifications, hypridle/hyprlock, wallpaper + matugen theming, gammastep
        night light, clipboard manager, satty screenshots) on top of
        {option}`hyprland.enable`.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    wayland.windowManager.hyprland = {
      enable = true;
      # The settings below are written in the classic hyprlang syntax, so pin
      # the generator to it (newer home-manager defaults to the Lua config).
      configType = "hyprlang";
      # On NixOS the compositor comes from programs.hyprland (desktop/hyprland.nix);
      # on CachyOS there is no NixOS layer, so home-manager provides the binary.
      package = lib.mkIf (!config.commonHm.isCachyOS) null;
      systemd.enable = true;

      # Hyprspace workspace overview (SUPER+`), where the plugin ABI matches.
      plugins = lib.optionals hasOverview [ pkgs.hyprlandPlugins.hyprspace ];

      settings = {
        # $mod is the Omarchy SUPER key.
        "$mod" = mod;

        # Generated by the omarchy-theme activation from the wallpaper; defines
        # $accent / $inactive. sourceFirst puts this before the colours are used.
        source = [ "${config.xdg.configHome}/omarchy/hypr-colors.conf" ];

        monitor = ", preferred, auto, auto";

        # Omarchy default/hypr/looknfeel.lua: flat, no rounding, no blur or
        # shadows. The accent border comes from the generated theme ($accent).
        general = {
          gaps_in = 5;
          gaps_out = 10;
          border_size = 2;
          "col.active_border" = "$accent";
          "col.inactive_border" = "$inactive";
          layout = "dwindle";
          resize_on_border = false;
          allow_tearing = false;
        };

        decoration = {
          rounding = 0;
          shadow.enabled = false;
          blur.enabled = false;
        };

        group = {
          "col.border_active" = "$accent";
          "col.border_inactive" = "$inactive";
          groupbar = {
            font_size = 12;
            font_family = "monospace";
            font_weight_active = "ultraheavy";
            font_weight_inactive = "normal";
            indicator_height = 1;
            indicator_gap = 5;
            height = 22;
            gaps_in = 5;
            gaps_out = 0;
            text_color = "rgb(ffffff)";
            text_color_inactive = "rgba(ffffff90)";
            "col.active" = "rgba(00000040)";
            "col.inactive" = "rgba(00000020)";
            gradients = true;
            gradient_rounding = 0;
            gradient_round_only_edges = false;
          };
        };

        # Omarchy's default animation curves and per-leaf timings.
        animations = {
          enabled = true;
          bezier = [
            "easeOutQuint, 0.23, 1, 0.32, 1"
            "easeInOutCubic, 0.65, 0.05, 0.36, 1"
            "linear, 0, 0, 1, 1"
            "almostLinear, 0.5, 0.5, 0.75, 1"
            "quick, 0.15, 0, 0.1, 1"
          ];
          animation = [
            "global, 1, 10, default"
            "border, 1, 5.39, easeOutQuint"
            "windows, 1, 3.79, easeOutQuint"
            "windowsIn, 1, 4.1, easeOutQuint, popin 87%"
            "windowsOut, 1, 1.49, linear, popin 87%"
            "fadeIn, 1, 1.73, almostLinear"
            "fadeOut, 1, 1.46, almostLinear"
            "fade, 1, 3.03, quick"
            "fadeSwitch, 0"
            "layers, 1, 3.81, easeOutQuint"
            "layersIn, 1, 4, easeOutQuint, fade"
            "layersOut, 1, 1.5, linear, fade"
            "fadeLayersIn, 1, 1.79, almostLinear"
            "fadeLayersOut, 1, 1.39, almostLinear"
            "workspaces, 0"
          ];
        };

        dwindle = {
          preserve_split = true;
          force_split = 2;
        };

        scrolling.column_width = 0.49;

        master.new_status = "master";

        misc = {
          disable_hyprland_logo = true;
          disable_splash_rendering = true;
          disable_scale_notification = true;
          focus_on_activate = true;
          anr_missed_pings = 3;
          on_focus_under_fullscreen = 1;
          initial_workspace_tracking = 0;
          allow_session_lock_restore = true;
          key_press_enables_dpms = true;
          mouse_move_enables_dpms = true;
        };

        cursor = {
          hide_on_key_press = true;
          warp_on_change_workspace = 1;
        };

        binds.hide_special_on_workspace_change = true;

        xwayland.force_zero_scaling = true;

        # Omarchy default/hypr/input.lua. Layout is the household's Belgian
        # (be) rather than Omarchy's us, matching desktop/xserver.nix.
        input = {
          kb_layout = "be";
          kb_options = "compose:caps,shift:both_capslock_cancel";
          follow_mouse = 1;
          sensitivity = 0;
          repeat_rate = 40;
          repeat_delay = 250;
          numlock_by_default = true;
          touchpad = {
            # Omarchy defaults this off; the household uses natural scrolling
            # (users/natural-scroll.nix, KDE), kept consistent here.
            natural_scroll = true;
            clickfinger_behavior = true;
            scroll_factor = 0.4;
          };
        };

        ecosystem.no_update_news = true;

        # Omarchy default/hypr/envs.lua.
        env = [
          "XCURSOR_SIZE,24"
          "HYPRCURSOR_SIZE,24"
          "GDK_BACKEND,wayland,x11,*"
          "QT_QPA_PLATFORM,wayland;xcb"
          "QT_QPA_PLATFORMTHEME,gtk3"
          "MOZ_ENABLE_WAYLAND,1"
          "ELECTRON_OZONE_PLATFORM_HINT,wayland"
          "OZONE_PLATFORM,wayland"
          "GTK_USE_PORTAL,1"
          "XDG_SESSION_TYPE,wayland"
          "XDG_CURRENT_DESKTOP,Hyprland"
          "XDG_SESSION_DESKTOP,Hyprland"
        ];

        # Three-finger horizontal touchpad swipe switches workspaces.
        gesture = [
          "3, horizontal, workspace"
        ];

        # Omarchy default/hypr/windows.lua + input.lua's per-app touchpad
        # scroll factors. Terminals get Omarchy's transparency treatment.
        windowrulev2 = [
          "suppressevent maximize, class:.*"
          "scroll_touchpad 1.5, class:^(Alacritty|kitty)$"
          "scroll_touchpad 2.0, class:^foot$"
          "scroll_touchpad 0.2, class:^com\\.mitchellh\\.ghostty$"
          "opacity 0.97 0.90, class:^(Alacritty|kitty|foot)$"
        ];

        bind = coreBinds ++ mediaBinds
          ++ lib.optionals hasOverview overviewBinds
          ++ lib.optionals cfg.omarchy omarchyBinds;

        bindm = [
          "${mod}, mouse:272, movewindow"
          "${mod}, mouse:273, resizewindow"
        ];
      } // lib.optionalAttrs hasOverview {
        # Hyprspace overview styling (Omarchy-ish dark panel, Catppuccin accent).
        plugin.overview = {
          panelColor = "rgba(1e1e2eee)";
          panelBorderColor = "rgba(89b4faff)";
          panelBorderWidth = 2;
          workspaceActiveBackground = "rgba(49,50,68,0.85)";
          workspaceInactiveBackground = "rgba(24,24,37,0.65)";
          workspaceActiveBorder = "rgb(89b4fa)";
          workspaceInactiveBorder = "rgb(69,71,90)";
          centerAligned = true;
          autoDrag = true;
          exitOnClick = true;
          switchOnDrop = true;
          showNewWorkspace = true;
        };
      };

      # Autostart the session extras. The Quickshell bar is started by its own
      # home-manager systemd service (programs.quickshell below).
      extraConfig = ''
        exec-once = ${pkgs.hyprpolkitagent}/bin/hyprpolkitagent
        # Screen blank + lock on idle (see hypr/hypridle.conf below); on by
        # default for every user, not just the omarchy profile.
        exec-once = ${pkgs.hypridle}/bin/hypridle
      '' + lib.optionalString cfg.omarchy ''
        exec-once = ${pkgs.mako}/bin/mako
        exec-once = ${pkgs.swayosd}/bin/swayosd-server
        exec-once = ${pkgs.hyprpaper}/bin/hyprpaper
        # Record clipboard history for the cliphist picker bound to SUPER+CTRL+V.
        exec-once = ${pkgs.wl-clipboard}/bin/wl-paste --watch ${pkgs.cliphist}/bin/cliphist store
        # Removable-drive automount and the network/bluetooth tray applets that
        # Plasma otherwise provides itself. They surface in the Quickshell bar.
        exec-once = ${pkgs.udiskie}/bin/udiskie --automount --notify
        exec-once = ${pkgs.networkmanagerapplet}/bin/nm-applet --indicator
        exec-once = ${pkgs.blueman}/bin/blueman-applet
        # KWallet daemon (same secret service KDE uses; unlocked via PAM).
        exec-once = ${pkgs.kdePackages.kwallet}/bin/kwalletd6
      '';
    };

    # Automatic night light: gammastep shifts the colour temperature at sunset
    # for the household's location (Luxembourg). Toggle with SUPER+CTRL+N.
    systemd.user.services.gammastep = lib.mkIf cfg.omarchy {
      Unit = {
        Description = "gammastep automatic night light";
        PartOf = [ "graphical-session.target" ];
        After = [ "graphical-session.target" ];
      };
      Service = {
        ExecStart = "${pkgs.gammastep}/bin/gammastep -l 49.61:6.13 -t 6500:4000";
        Restart = "on-failure";
        RestartSec = 10;
      };
      Install.WantedBy = [ "hyprland-session.target" ];
    };

    # Generate the matugen theme (colours.json + hypr-colors.conf) on first
    # switch only, so a user's own re-theme (`omarchy-theme <image>`) survives
    # later switches. Delete the file to regenerate the default.
    home.activation.omarchyTheme =
      lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        if [ ! -e "${config.xdg.configHome}/omarchy/colors.json" ]; then
          $DRY_RUN_CMD ${theme}
        fi
      '';

    # The Quickshell bar (users/quickshell/omarchy), started as a user service
    # with the Hyprland session.
    programs.quickshell = {
      enable = true;
      configs.omarchy = ./quickshell/omarchy;
      activeConfig = "omarchy";
      systemd.enable = true;
      systemd.target = "hyprland-session.target";
    };

    xdg.portal.enable = true;
    xdg.portal.extraPortals = [ pkgs.xdg-desktop-portal-gtk ];

    # GNOME/GTK theming so libadwaita and GTK apps follow the Omarchy dark look
    # in a Wayland session (Plasma themes its own GTK apps). Gated to the
    # omarchy profile so it does not fight KDE's kde-gtk-config.
    gtk = lib.mkIf cfg.omarchy {
      enable = true;
      theme = { name = "adw-gtk3-dark"; package = pkgs.adw-gtk3; };
      iconTheme = { name = "Adwaita"; package = pkgs.adwaita-icon-theme; };
      cursorTheme = { name = "Adwaita"; package = pkgs.adwaita-icon-theme; size = 24; };
      gtk3.extraConfig.gtk-application-prefer-dark-theme = 1;
      gtk4.extraConfig.gtk-application-prefer-dark-theme = 1;
    };
    dconf.enable = lib.mkIf cfg.omarchy true;
    dconf.settings = lib.mkIf cfg.omarchy {
      "org/gnome/desktop/interface" = {
        color-scheme = "prefer-dark";
        gtk-theme = "adw-gtk3-dark";
        icon-theme = "Adwaita";
        cursor-theme = "Adwaita";
        monospace-font-name = "FiraCode Nerd Font Mono 11";
      };
    };

    home.packages = with pkgs;
      [
        quickshell
        alacritty
        wl-clipboard
        grim
        slurp
        brightnessctl
        playerctl
        hypridle
        hyprlock
      ]
      ++ lib.optionals cfg.omarchy [
        walker
        fuzzel
        nwg-displays
        mako
        swayosd
        cliphist
        udiskie
        wf-recorder
        satty
        hyprshot
        hyprpicker
        hyprpaper
        gammastep
        hyprpolkitagent
        power-profiles-daemon
        matugen
        theme
        rofimoji
        qalculate-qt
        tesseract
        kdePackages.kwallet
        kdePackages.kwalletmanager
        libnotify
        pavucontrol
        networkmanagerapplet
        blueman
      ];

    # hypridle/hyprlock configs are installed for every user (screen blank at
    # 2.5 min, lock at 5 min, and lock before suspend, like Omarchy's defaults).
    # The mako/hyprpaper configs are omarchy-profile extras.
    xdg.configFile = {
      "hypr/hypridle.conf".text = ''
        general {
          lock_cmd = ${pkgs.hyprlock}/bin/hyprlock
          before_sleep_cmd = ${pkgs.systemd}/bin/loginctl lock-session
          after_sleep_cmd = ${pkgs.hyprland}/bin/hyprctl dispatch dpms on
        }

        listener {
          timeout = 150
          on-timeout = ${pkgs.hyprland}/bin/hyprctl dispatch dpms off
          on-resume = ${pkgs.hyprland}/bin/hyprctl dispatch dpms on
        }

        listener {
          timeout = 300
          on-timeout = ${pkgs.hyprlock}/bin/hyprlock
        }
      '';
      "hypr/hyprlock.conf".text = ''
        background {
          monitor =
          color = rgba(30, 30, 46, 1.0)
        }

        input-field {
          size = 240, 44
          outline_thickness = 2
          dots_size = 0.25
          rounding = 8
          inner_color = rgba(49, 50, 68, 1.0)
          font_color = rgba(205, 214, 244, 1.0)
          outline_color = rgba(137, 180, 250, 1.0)
          check_color = rgba(137, 180, 250, 1.0)
          fail_color = rgba(243, 139, 168, 1.0)
          placeholder_text = Password...
          position = 0, -40
          halign = center
          valign = center
        }

        label {
          text = $TIME
          color = rgba(205, 214, 244, 1.0)
          font_size = 72
          font_family = monospace
          position = 0, 120
          halign = center
          valign = center
        }
      '';
    } // lib.optionalAttrs cfg.omarchy {
      # mako: Omarchy-flavoured notifications, with a Do Not Disturb mode toggled
      # by SUPER+CTRL+, (makoctl mode -t do-not-disturb).
      "mako/config".text = ''
        font=monospace 10
        background-color=#1e1e2e
        text-color=#cdd6f4
        border-color=#89b4fa
        border-size=2
        border-radius=8
        padding=12
        margin=8
        width=380
        height=150
        anchor=top-right
        default-timeout=5000
        max-visible=5
        layer=overlay

        [urgency=critical]
        border-color=#f38ba8
        default-timeout=0

        [mode=do-not-disturb]
        invisible=1
      '';
      "hypr/hyprpaper.conf".text = ''
        preload = ${defaultWallpaper}/wallpaper.png
        wallpaper = ,${defaultWallpaper}/wallpaper.png
        splash = false
      '';
    };
  };
}
