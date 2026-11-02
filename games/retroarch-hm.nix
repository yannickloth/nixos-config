# Per-user RetroArch baseline configuration.
#
# RetroArch is installed system-wide (games/games.nix) with the retro cores
# bundled (retroarch.withCores), so every user can start it; this module only
# ships the per-user ~/.config/retroarch/retroarch.cfg baseline:
#
#   - low-latency settings (run-ahead + frame delay)
#   - RetroAchievements enabled (hardcore mode on)
#   - system/BIOS directory pointed at the shared ROM library
#
# WHY A COPY-ONCE ACTIVATION AND NOT A home-manager-MANAGED FILE: RetroArch
# rewrites retroarch.cfg completely on every exit (menu settings, core options)
# AND stores the RetroAchievements login token in it. A managed symlink to the
# nix store is read-only, so the rewrite fails silently and the login token is
# lost on every restart. The baseline is therefore installed as a real file
# once, after which RetroArch owns the file (the baseline keys persist because
# RetroArch round-trips them).
#
# Home-manager symlinks the same baseline next to it (00-baseline.cfg) so a
# "reset my baseline" is possible by copying it over retroarch.cfg by hand.
#
# NOTE: if a user had ALREADY run RetroArch before this module landed, the
# retrofit step below respects the values already in their config (it only
# appends missing keys). Turn achievements on once via the menu in that case.
{ config, lib, pkgs, ... }:

{
  options.commonHm.retroarch = lib.mkOption {
    type = lib.types.bool;
    default = true;
    description = "Whether to install the per-user RetroArch baseline configuration (copy-once retroarch.cfg with run-ahead/frame delay and RetroAchievements defaults).";
  };

  config = lib.mkIf config.commonHm.retroarch {
    xdg.configFile."retroarch/00-baseline.cfg".source = pkgs.writeText "retroarch-baseline.cfg" ''
      # Baseline installed by games/retroarch-hm.nix (copy-once). RetroArch
      # round-trips every key below into its own retroarch.cfg.
      # --- Low latency ---
      run_ahead = "true"
      run_ahead_frames = "1"
      run_ahead_hide_warnings = "true"
      frame_delay = "0" # 0 = auto; tune 0-3 if a core drops frames
      # --- RetroAchievements (retroachievements.org) ---
      cheevos_enable = "true"
      cheevos_hardcore_mode_enable = "true"
      # --- Directories ---
      # System/BIOS files of the shared family ROM library. ~/sync links to
      # /sync, but an absolute path keeps working no matter how the content
      # is browsed (and on hosts where /sync is absent it is simply unused).
      system_directory = "/sync/90-99 - Public stuff/roms/BIOS"
    '';

    home.activation.retroarchBaseline = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      cfgDir="$HOME/.config/retroarch"
      cfg="$cfgDir/retroarch.cfg"
      mkdir -p "$cfgDir"
      if [ ! -f "$cfg" ]; then
        $DRY_RUN_CMD ${pkgs.coreutils}/bin/install -m 644 "$cfgDir/00-baseline.cfg" "$cfg"
      else
        # Retrofit missing baseline keys into an existing config: existing
        # values (a saved RetroAchievements token, personal tweaks) are kept,
        # so appending is safe. Only key lines from the baseline are checked;
        # comments and the appended order do not matter to RetroArch.
        while IFS= read -r line; do
          [ "''${line:0:1}" = "#" ] && continue
          key="''${line%% =*}"
          [ -n "$key" ] || continue
          $DRY_RUN_CMD ${pkgs.gnugrep}/bin/grep -q "^$key =" "$cfg" \
            || printf '%s\n' "$line" >> "$cfg"
        done < "$cfgDir/00-baseline.cfg"
      fi
    '';
  };
}
