# Natural (inverse) scrolling for all mice and touchpads.
#
# KDE Plasma (X11 session) reads ~/.config/kcminputrc at login and applies the
# libinput settings to every pointer/touchpad device. We merge the natural-scroll
# keys into the existing file (via python3 configparser, same pattern as the
# malcontent accountsservice merge) so the user's other input settings are kept.
{ config, lib, pkgs, ... }:

{
  home.activation.setNaturalScroll = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    ${pkgs.python3}/bin/python3 - <<'PY'
import configparser, os

path = os.path.expanduser("~/.config/kcminputrc")
cfg = configparser.ConfigParser(interpolation=None)
cfg.optionxform = str  # preserve key case (XLbInptNaturalScroll)
if os.path.exists(path):
    cfg.read(path)
for section in ("Mouse", "Touchpad"):
    if not cfg.has_section(section):
        cfg.add_section(section)
    cfg.set(section, "XLbInptNaturalScroll", "true")
with open(path, "w") as f:
    cfg.write(f, space_around_delimiters=False)
PY
  '';
}
