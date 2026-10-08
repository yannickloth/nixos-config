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

  # The running compositor's own hyprctl must be used; calling another
  # version's binary over IPC is fragile. On NixOS that is the system
  # programs.hyprland build; on CachyOS it is the pacman one, which is on PATH
  # (home-manager no longer installs Hyprland there, see `package` below).
  hyprctl = if config.commonHm.isCachyOS then "hyprctl" else "${pkgs.hyprland}/bin/hyprctl";

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
  # colors.json (Quickshell) and hypr-colors.lua (Hyprland). Falls back to a
  # Catppuccin palette if matugen/jq yield nothing, so a bad run never leaves
  # the desktop unstyled.
  theme = pkgs.writeShellScriptBin "omarchy-theme" ''
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

    cat > "$dir/hypr-colors.lua" <<EOF
    return { accent = "$(hexff "$accent")", inactive = "rgba(595959aa)" }
    EOF

    if ${pkgs.procps}/bin/pgrep -x Hyprland >/dev/null 2>&1; then
      ${pkgs.hyprland}/bin/hyprctl reload >/dev/null 2>&1 || true
    fi
  '';

  # Window/workspace management, modelled on Omarchy's defaults.
  # --- Lua config helpers ---------------------------------------------------
  # home-manager's Lua generator (configType = "lua") turns each attribute of
  # `settings` into an `hl.<attr>(...)` call. Dispatchers are opaque objects
  # (hl.dsp.*) that cannot be built from Nix data, so they are emitted verbatim
  # with lib.generators.mkLuaInline.
  lua = lib.generators.mkLuaInline;

  # hl.bind("<keys>", <dispatcher>[, <opts>]).
  luaBind = keys: dispatcher: opts: {
    _args = [ keys (lua dispatcher) ] ++ lib.optional (opts != null) opts;
  };
  # A `exec` bind (the common case): hl.dsp.exec_cmd("<cmd>").
  execBind = keys: cmd: luaBind keys "hl.dsp.exec_cmd(${builtins.toJSON cmd})" null;

  # Runtime matugen palette (see omarchy-theme). pcall + Catppuccin fallback so
  # a missing or partial hypr-colors.lua never breaks config parsing.
  themeColors = "${config.xdg.configHome}/omarchy/hypr-colors.lua";
  color = key: fallback: lua ''
    (function()
      local ok, c = pcall(dofile, "${themeColors}")
      if ok and type(c) == "table" and c.${key} then return c.${key} end
      return "${fallback}"
    end)()
  '';
  colors = {
    accent = color "accent" "rgba(89b4faff)";
    inactive = color "inactive" "rgba(595959aa)";
  };

  # Window/workspace management, modelled on Omarchy's defaults.
  coreBinds = [
    (execBind "${mod} + RETURN" "${pkgs.alacritty}/bin/alacritty")
    (luaBind "${mod} + Q" "hl.dsp.window.close()" null)
    (luaBind "${mod} + W" "hl.dsp.window.close()" null)
    (luaBind "${mod} + F" "hl.dsp.window.fullscreen({ mode = 0 })" null)
    (luaBind "${mod} + CTRL + F" "hl.dsp.window.fullscreen({ mode = 1 })" null)
    (luaBind "${mod} + T" "hl.dsp.window.float({ action = 'toggle' })" null)
    (luaBind "${mod} + P" "hl.dsp.window.pseudo()" null)
    (luaBind "${mod} + J" "hl.dsp.layout('togglesplit')" null)
    (luaBind "${mod} + M" "hl.dsp.exit()" null)

    (luaBind "${mod} + left" "hl.dsp.focus({ direction = 'l' })" null)
    (luaBind "${mod} + right" "hl.dsp.focus({ direction = 'r' })" null)
    (luaBind "${mod} + up" "hl.dsp.focus({ direction = 'u' })" null)
    (luaBind "${mod} + down" "hl.dsp.focus({ direction = 'd' })" null)
    (luaBind "${mod} + SHIFT + left" "hl.dsp.window.swap({ direction = 'l' })" null)
    (luaBind "${mod} + SHIFT + right" "hl.dsp.window.swap({ direction = 'r' })" null)
    (luaBind "${mod} + SHIFT + up" "hl.dsp.window.swap({ direction = 'u' })" null)
    (luaBind "${mod} + SHIFT + down" "hl.dsp.window.swap({ direction = 'd' })" null)

    (luaBind "${mod} + CTRL + left" "hl.dsp.window.resize({ x = -100, y = 0, relative = true })" null)
    (luaBind "${mod} + CTRL + right" "hl.dsp.window.resize({ x = 100, y = 0, relative = true })" null)
    (luaBind "${mod} + CTRL + up" "hl.dsp.window.resize({ x = 0, y = -100, relative = true })" null)
    (luaBind "${mod} + CTRL + down" "hl.dsp.window.resize({ x = 0, y = 100, relative = true })" null)
    (luaBind "${mod} + ALT + left" "hl.dsp.window.resize({ x = -25, y = 0, relative = true })" null)
    (luaBind "${mod} + ALT + right" "hl.dsp.window.resize({ x = 25, y = 0, relative = true })" null)
    (luaBind "${mod} + ALT + up" "hl.dsp.window.resize({ x = 0, y = -25, relative = true })" null)
    (luaBind "${mod} + ALT + down" "hl.dsp.window.resize({ x = 0, y = 25, relative = true })" null)

    (luaBind "${mod} + S" "hl.dsp.workspace.toggle_special('scratchpad')" null)
    (luaBind "${mod} + SHIFT + S" "hl.dsp.window.move({ workspace = 'special:scratchpad' })" null)
    (luaBind "${mod} + TAB" "hl.dsp.focus({ workspace = 'e+1' })" null)
    (luaBind "${mod} + SHIFT + TAB" "hl.dsp.focus({ workspace = 'e-1' })" null)
    (luaBind "${mod} + CTRL + TAB" "hl.dsp.focus({ workspace = 'previous' })" null)
  ]
  # SUPER + 1..0 -> switch workspace; SUPER + SHIFT + 1..0 -> move window there.
  ++ (lib.concatMap
    (n: [
      (luaBind "${mod} + ${toString (lib.mod n 10)}" "hl.dsp.focus({ workspace = ${toString n} })" null)
      (luaBind "${mod} + SHIFT + ${toString (lib.mod n 10)}" "hl.dsp.window.move({ workspace = ${toString n} })" null)
    ])
    (lib.range 1 10));

  # Mouse move/resize binds; `{ mouse = true }` marks the bind as a mouse bind.
  mouseBinds = [
    (luaBind "${mod} + mouse:272" "hl.dsp.window.drag()" { mouse = true; })
    (luaBind "${mod} + mouse:273" "hl.dsp.window.resize()" { mouse = true; })
  ];

  # Hardware/media keys (no modifier). With the Omarchy profile these go
  # through swayosd-client so volume/brightness show Omarchy's on-screen
  # display; the base profile uses wpctl/brightnessctl (no OSD).
  mediaBinds =
    if cfg.omarchy then [
      (execBind "XF86AudioRaiseVolume" "${pkgs.swayosd}/bin/swayosd-client --output-volume raise")
      (execBind "XF86AudioLowerVolume" "${pkgs.swayosd}/bin/swayosd-client --output-volume lower")
      (execBind "XF86AudioMute" "${pkgs.swayosd}/bin/swayosd-client --output-volume mute-toggle")
      (execBind "XF86AudioMicMute" "${pkgs.swayosd}/bin/swayosd-client --input-volume mute-toggle")
      (execBind "XF86MonBrightnessUp" "${pkgs.swayosd}/bin/swayosd-client --brightness raise")
      (execBind "XF86MonBrightnessDown" "${pkgs.swayosd}/bin/swayosd-client --brightness lower")
      (execBind "XF86AudioPlay" "${pkgs.playerctl}/bin/playerctl play-pause")
      (execBind "XF86AudioNext" "${pkgs.playerctl}/bin/playerctl next")
      (execBind "XF86AudioPrev" "${pkgs.playerctl}/bin/playerctl previous")
    ] else [
      (execBind "XF86AudioRaiseVolume" "${pkgs.wireplumber}/bin/wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%+")
      (execBind "XF86AudioLowerVolume" "${pkgs.wireplumber}/bin/wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-")
      (execBind "XF86AudioMute" "${pkgs.wireplumber}/bin/wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle")
      (execBind "XF86AudioMicMute" "${pkgs.wireplumber}/bin/wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle")
      (execBind "XF86AudioPlay" "${pkgs.playerctl}/bin/playerctl play-pause")
      (execBind "XF86AudioNext" "${pkgs.playerctl}/bin/playerctl next")
      (execBind "XF86AudioPrev" "${pkgs.playerctl}/bin/playerctl previous")
      (execBind "XF86MonBrightnessUp" "${pkgs.brightnessctl}/bin/brightnessctl set 5%+")
      (execBind "XF86MonBrightnessDown" "${pkgs.brightnessctl}/bin/brightnessctl set 5%-")
    ];

  # Overview (GNOME Activities equivalent), only where the plugin can load.
  # hyprspace registers a dispatcher, invoked here through hyprctl so the bind
  # works regardless of the Lua plugin-dispatcher API.
  overviewBinds = [
    (execBind "${mod} + grave" "${hyprctl} dispatch overview:toggle")
  ];

  # Omarchy extras: launcher, app launchers, screenshots, clipboard, lock,
  # night light. Mirrors Omarchy's default/hypr/bindings/applications.lua plus
  # the utilities. Apps go through xdg-open so they work regardless of which
  # browser/editor a user has.
  omarchyBinds = [
    (execBind "${mod} + SPACE" "${pkgs.walker}/bin/walker")
    (execBind "${mod} + SHIFT + RETURN" "xdg-open https://")
    (execBind "${mod} + SHIFT + B" "xdg-open https://")
    (execBind "${mod} + SHIFT + F" "xdg-open ~")
    (execBind "${mod} + SHIFT + N" "xdg-open .")
    (execBind "PRINT" "${screenshotOutput}")
    (execBind "${mod} + PRINT" "${pkgs.hyprpicker}/bin/hyprpicker -a")
    (execBind "${mod} + SHIFT + PRINT" "${screenshotRegion}")
    (execBind "${mod} + ALT + PRINT" "${screenrecord}")
    (execBind "${mod} + CTRL + V" "${pkgs.cliphist}/bin/cliphist list | ${pkgs.fuzzel}/bin/fuzzel --dmenu | ${pkgs.cliphist}/bin/cliphist decode | ${pkgs.wl-clipboard}/bin/wl-copy")
    (execBind "${mod} + CTRL + L" "${pkgs.hyprlock}/bin/hyprlock")
    # Night light: gammastep runs on a schedule; SIGUSR1 toggles it.
    (execBind "${mod} + CTRL + N" "${pkgs.procps}/bin/pkill -USR1 gammastep")
    # Display arrangement (like Plasma's display settings) and keybindings help.
    (execBind "${mod} + CTRL + D" "${pkgs.nwg-displays}/bin/nwg-displays")
    (execBind "${mod} + K" "${keybindings}")
    # OCR a screen region to the clipboard.
    (execBind "${mod} + CTRL + PRINT" "${screenocr}")
    # Emoji picker and calculator.
    (execBind "${mod} + CTRL + E" "${pkgs.rofimoji}/bin/rofimoji --selector fuzzel --clipboard")
    (execBind "${mod} + CTRL + Q" "${pkgs.qalculate-qt}/bin/qalculate-qt")
    # Notifications / Do Not Disturb, matching Omarchy's SUPER+, binds.
    (execBind "${mod} + comma" "${pkgs.mako}/bin/makoctl dismiss")
    (execBind "${mod} + SHIFT + comma" "${pkgs.mako}/bin/makoctl dismiss --all")
    (execBind "${mod} + CTRL + comma" "${pkgs.mako}/bin/makoctl mode -t do-not-disturb")
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
      # Lua is the current Hyprland config format (hyprlang is deprecated since
      # 0.55); home-manager generates $XDG_CONFIG_HOME/hypr/hyprland.lua.
      configType = "lua";
      # The compositor is always installed by the system, never by home-manager:
      # on NixOS by programs.hyprland (desktop/hyprland.nix), on CachyOS by the
      # pacman `hyprland` package (which also drops the SDDM session entry into
      # /usr/share/wayland-sessions). Home Manager only writes the config here,
      # so it must not pull in a second Hyprland from the Nix profile.
      package = null;
      # Same reasoning for the portal: on CachyOS the pacman
      # xdg-desktop-portal-hyprland is built against the same compositor, so
      # home-manager must not install the nixpkgs one alongside it (nor point
      # xdg-desktop-portal at the Nix profile). On NixOS home-manager's portal
      # is used as before.
      portalPackage = lib.mkIf config.commonHm.isCachyOS null;
      systemd.enable = true;

      # Hyprspace workspace overview (SUPER+`), where the plugin ABI matches.
      plugins = lib.optionals hasOverview [ pkgs.hyprlandPlugins.hyprspace ];

      settings = {
        # Option blocks are written under `config` (-> hl.config({...})); the
        # rest map to their hl.* call (hl.monitor, hl.env, hl.curve, ...).
        config = {
          # Omarchy default/hypr/looknfeel.lua: flat, no rounding, no blur or
          # shadows. The accent border comes from the generated theme.
          general = {
            gaps_in = 5;
            gaps_out = 10;
            border_size = 2;
            col = {
              active_border = colors.accent;
              inactive_border = colors.inactive;
            };
            layout = "dwindle";
            resize_on_border = false;
            allow_tearing = false;
          };

          decoration = {
            rounding = 0;
            shadow = { enabled = false; };
            blur = { enabled = false; };
          };

          group = {
            col = {
              border_active = colors.accent;
              border_inactive = colors.inactive;
            };
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
              col = {
                active = "rgba(00000040)";
                inactive = "rgba(00000020)";
              };
              gradients = true;
              gradient_rounding = 0;
              gradient_round_only_edges = false;
            };
          };

          animations = { enabled = true; };

          dwindle = {
            preserve_split = true;
            force_split = 2;
          };

          scrolling = { column_width = 0.49; };

          master = { new_status = "master"; };

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

          binds = { hide_special_on_workspace_change = true; };

          xwayland = { force_zero_scaling = true; };

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

          ecosystem = { no_update_news = true; };
        }
        // lib.optionalAttrs hasOverview {
          # Hyprspace overview styling (Omarchy-ish dark panel, Catppuccin).
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

        monitor = [{
          output = "";
          mode = "preferred";
          position = "auto";
          scale = "auto";
        }];

        # Omarchy default/hypr/envs.lua.
        env = [
          { _args = [ "XCURSOR_SIZE" "24" ]; }
          { _args = [ "HYPRCURSOR_SIZE" "24" ]; }
          { _args = [ "GDK_BACKEND" "wayland,x11,*" ]; }
          { _args = [ "QT_QPA_PLATFORM" "wayland;xcb" ]; }
          { _args = [ "QT_QPA_PLATFORMTHEME" "gtk3" ]; }
          { _args = [ "MOZ_ENABLE_WAYLAND" "1" ]; }
          { _args = [ "ELECTRON_OZONE_PLATFORM_HINT" "wayland" ]; }
          { _args = [ "OZONE_PLATFORM" "wayland" ]; }
          { _args = [ "GTK_USE_PORTAL" "1" ]; }
          { _args = [ "XDG_SESSION_TYPE" "wayland" ]; }
          { _args = [ "XDG_CURRENT_DESKTOP" "Hyprland" ]; }
          { _args = [ "XDG_SESSION_DESKTOP" "Hyprland" ]; }
        ];

        # Omarchy's default animation curves and per-leaf timings.
        curve = [
          { _args = [ "easeOutQuint" { type = "bezier"; points = [ [ 0.23 1 ] [ 0.32 1 ] ]; } ]; }
          { _args = [ "easeInOutCubic" { type = "bezier"; points = [ [ 0.65 0.05 ] [ 0.36 1 ] ]; } ]; }
          { _args = [ "linear" { type = "bezier"; points = [ [ 0 0 ] [ 1 1 ] ]; } ]; }
          { _args = [ "almostLinear" { type = "bezier"; points = [ [ 0.5 0.5 ] [ 0.75 1 ] ]; } ]; }
          { _args = [ "quick" { type = "bezier"; points = [ [ 0.15 0 ] [ 0.1 1 ] ]; } ]; }
        ];

        animation = [
          { leaf = "global"; enabled = true; speed = 10; bezier = "default"; }
          { leaf = "border"; enabled = true; speed = 5.39; bezier = "easeOutQuint"; }
          { leaf = "windows"; enabled = true; speed = 3.79; bezier = "easeOutQuint"; }
          { leaf = "windowsIn"; enabled = true; speed = 4.1; bezier = "easeOutQuint"; style = "popin 87%"; }
          { leaf = "windowsOut"; enabled = true; speed = 1.49; bezier = "linear"; style = "popin 87%"; }
          { leaf = "fadeIn"; enabled = true; speed = 1.73; bezier = "almostLinear"; }
          { leaf = "fadeOut"; enabled = true; speed = 1.46; bezier = "almostLinear"; }
          { leaf = "fade"; enabled = true; speed = 3.03; bezier = "quick"; }
          { leaf = "fadeSwitch"; enabled = false; }
          { leaf = "layers"; enabled = true; speed = 3.81; bezier = "easeOutQuint"; }
          { leaf = "layersIn"; enabled = true; speed = 4; bezier = "easeOutQuint"; style = "fade"; }
          { leaf = "layersOut"; enabled = true; speed = 1.5; bezier = "linear"; style = "fade"; }
          { leaf = "fadeLayersIn"; enabled = true; speed = 1.79; bezier = "almostLinear"; }
          { leaf = "fadeLayersOut"; enabled = true; speed = 1.39; bezier = "almostLinear"; }
          { leaf = "workspaces"; enabled = false; }
        ];

        # Three-finger horizontal touchpad swipe switches workspaces.
        gesture = [
          { fingers = 3; direction = "horizontal"; action = "workspace"; }
        ];

        # Omarchy default/hypr/windows.lua + input.lua's per-app touchpad
        # scroll factors. Terminals get Omarchy's transparency treatment.
        # Hyprland >= 0.53 window rules: `windowrule = <rule>, match:<field> <value>`
        # (the old `windowrulev2`/`class:` form is deprecated in 0.56).
        window_rule = [
          { name = "suppress-maximize"; match = { class = ".*"; }; suppress_event = "maximize"; }
          { match = { class = "^(Alacritty|kitty)$"; }; scroll_touchpad = 1.5; }
          { match = { class = "^foot$"; }; scroll_touchpad = 2.0; }
          { match = { class = "^com\\.mitchellh\\.ghostty$"; }; scroll_touchpad = 0.2; }
          { match = { class = "^(Alacritty|kitty|foot)$"; }; opacity = "0.97 0.90"; }
        ];

        bind = coreBinds ++ mouseBinds ++ mediaBinds
          ++ lib.optionals hasOverview overviewBinds
          ++ lib.optionals cfg.omarchy omarchyBinds;
      };

      # Autostart the session extras (Lua: one hl.on("hyprland.start") hook).
      # The Quickshell bar is started by its own home-manager systemd service
      # (programs.quickshell below).
      extraConfig = lib.concatStringsSep "\n" ([
        ''hl.on("hyprland.start", function()''
        ''  hl.exec_cmd("${pkgs.hyprpolkitagent}/bin/hyprpolkitagent")''
        # Screen blank + lock on idle (see hypr/hypridle.conf below); on by
        # default for every user, not just the omarchy profile.
        ''  hl.exec_cmd("${pkgs.hypridle}/bin/hypridle")''
      ] ++ lib.optionals cfg.omarchy [
        ''  hl.exec_cmd("${pkgs.mako}/bin/mako")''
        ''  hl.exec_cmd("${pkgs.swayosd}/bin/swayosd-server")''
        ''  hl.exec_cmd("${pkgs.hyprpaper}/bin/hyprpaper")''
        # Record clipboard history for the cliphist picker bound to SUPER+CTRL+V.
        ''  hl.exec_cmd("${pkgs.wl-clipboard}/bin/wl-paste --watch ${pkgs.cliphist}/bin/cliphist store")''
        # Removable-drive automount and the network/bluetooth tray applets that
        # Plasma otherwise provides itself. They surface in the Quickshell bar.
        ''  hl.exec_cmd("${pkgs.udiskie}/bin/udiskie --automount --notify")''
        ''  hl.exec_cmd("${pkgs.networkmanagerapplet}/bin/nm-applet --indicator")''
        ''  hl.exec_cmd("${pkgs.blueman}/bin/blueman-applet")''
        # KWallet daemon (same secret service KDE uses; unlocked via PAM).
        ''  hl.exec_cmd("${pkgs.kdePackages.kwallet}/bin/kwalletd6")''
      ] ++ [ ''end)'' ]);
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

    # Generate the matugen theme (colors.json + hypr-colors.lua) on first
    # switch only, so a user's own re-theme (`omarchy-theme <image>`) survives
    # later switches. Delete the file to regenerate the default.
    home.activation.omarchyTheme =
      lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        if [ ! -e "${config.xdg.configHome}/omarchy/colors.json" ]; then
          $DRY_RUN_CMD ${theme}/bin/omarchy-theme
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

    # On CachyOS the system/pacman portal stack is used instead of home-manager
    # managing it (see portalPackage above); xdg.portal.enable must match the
    # module's own `finalPortalPackage != null`, so gate it the same way.
    xdg.portal.enable = !config.commonHm.isCachyOS;
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
