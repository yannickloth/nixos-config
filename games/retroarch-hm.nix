# Per-user RetroArch glue: controller profile + writable-dir fixes.
#
# The RetroArch install and its baseline settings live system-wide in
# games/games.nix (retroarch-bare.wrapper settings). This module handles the
# things that are per-user, or that RetroArch owns at runtime:
#
#   1. The family Xbox 360 wireless receiver controller profile is installed
#      (copy-once) into ~/.config/retroarch/autoconfig/ — the per-user dir
#      that games/games.nix points joypad_autoconfig_dir at. After the
#      install, RetroArch owns the file: "Save Controller Configuration"
#      (menu) rewrites it in place, so it must be a real user-writable file,
#      not a home-manager-managed symlink into the read-only store.
#
#   2. Existing users' ~/.config/retroarch/retroarch.cfg are re-pointed once
#      for the writable dirs the earlier wrapper pinned to read-only store
#      paths. RA's config hashmap keeps the FIRST occurrence of each key
#      (verified in the v1.22.2 source, config_file.c), so a user's cfg
#      beats the system append config for any key it contains — for users
#      who already ran RetroArch (and therefore have a cfg full of effective
#      values, store paths included) the first-launch seed alone would never
#      take effect. The rewrite is one-shot: RA round-trips every path
#      setting back into the cfg on every exit (config_save_file), so the
#      fixed values persist and the grep guard makes every later activation
#      a no-op.
#
# Both steps are idempotent; they run on every activation and converge.
{ config, lib, pkgs, ... }:

let
  # The family Xbox 360 wireless receiver profile, captured from
  # /home/nicky/.config/retroarch/autoconfig (RA-saved, known-good mapping;
  # vendor 1118 = 0x045e Microsoft, product 673 = 0x02a1 Xbox 360 receiver).
  # (Name without spaces: it becomes part of the nix store path, which the
  # activation script interpolates unquoted.)
  controllerProfile = pkgs.writeText "retroarch-xbox360-receiver.cfg" ''
    input_driver = "udev"
    input_device = "Xbox 360 Wireless Receiver"
    input_vendor_id = "1118"
    input_product_id = "673"
    input_b_btn = "0"
    input_y_btn = "2"
    input_select_btn = "6"
    input_start_btn = "8"
    input_up_btn = "11"
    input_down_btn = "12"
    input_left_btn = "13"
    input_right_btn = "14"
    input_a_btn = "1"
    input_x_btn = "3"
    input_l_btn = "4"
    input_r_btn = "5"
    input_l2_axis = "+2"
    input_r2_axis = "+5"
    input_l_x_plus_axis = "+0"
    input_l_x_minus_axis = "-0"
    input_l_y_plus_axis = "+1"
    input_l_y_minus_axis = "-1"
    input_r_x_plus_axis = "+3"
    input_r_x_minus_axis = "-3"
    input_r_y_plus_axis = "+4"
    input_r_y_minus_axis = "-4"
  '';
in
{
  options.commonHm.retroarch = lib.mkOption {
    type = lib.types.bool;
    default = true;
    description = "Install the per-user RetroArch controller profile and re-point RetroArch's writable directories out of the nix store.";
  };

  config = lib.mkIf config.commonHm.retroarch {
    home.activation.retroarchAutoconfig = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      autoconfigDir="$HOME/.config/retroarch/autoconfig"
      cfg="$HOME/.config/retroarch/retroarch.cfg"

      # 1) Family controller profile (copy-once; RA owns it afterwards).
      $DRY_RUN_CMD ${pkgs.coreutils}/bin/mkdir -p "$autoconfigDir"
      if [ ! -f "$autoconfigDir/Xbox 360 Wireless Receiver.cfg" ]; then
        $DRY_RUN_CMD ${pkgs.coreutils}/bin/install -m 644 "${controllerProfile}" "$autoconfigDir/Xbox 360 Wireless Receiver.cfg"
      fi

      # 2) Re-point the writable dirs in an existing cfg (no-op once fixed).
      #    RA writes these as `key = "value"`, one per line.
      fix_key() {
        key=$1; val=$2
        [ -f "$cfg" ] || return 0
        target=$(printf '%s = "%s"' "$key" "$val")
        ${pkgs.gnugrep}/bin/grep -qF -- "$target" "$cfg" && return 0
        if [ -n "''${DRY_RUN_CMD:-}" ]; then
          echo "retroarchAutoconfig: would set: $target" >&2
          return 0
        fi
        if ${pkgs.gnugrep}/bin/grep -q "^$key = " "$cfg"; then
          ${pkgs.gawk}/bin/awk -v k="$key" -v v="$target" \
            '$0 ~ ("^" k " = ") { print v; next } { print }' \
            "$cfg" > "$cfg.tmp" && ${pkgs.coreutils}/bin/mv "$cfg.tmp" "$cfg"
        else
          printf '\n%s\n' "$target" >> "$cfg"
        fi
      }
      # Where "Save Controller Configuration" writes profiles. `~` expands
      # to each user's $HOME inside RetroArch at load time.
      fix_key joypad_autoconfig_dir "~/.config/retroarch/autoconfig"
      # Shared family BIOS directory (matches the system-wide baseline). The
      # sync root is resolved like users/common-hm.nix does: the /sync mount
      # on NixOS, a real ~/sync on CachyOS (no system Syncthing there).
      if [ -d ${lib.escapeShellArg config.commonHm.syncDir} ]; then
        syncRoot=${lib.escapeShellArg config.commonHm.syncDir}
      else
        syncRoot="$HOME/sync"
      fi
      fix_key system_directory "$syncRoot"/${lib.escapeShellArg config.commonHm.romsSubdir}/BIOS
    '';
  };
}
