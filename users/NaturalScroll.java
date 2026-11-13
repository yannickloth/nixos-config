// Natural (inverse) scrolling for all mice and touchpads.
//
// Merges the natural-scroll keys into KDE's ~/.config/kcminputrc:
//
//   Plasma 6 (KWin >= 6.0, src/backends/libinput/connection.cpp): KWin applies
//   input settings from class-default sections at session start and on every
//   device connect:
//     [Libinput][Defaults][Pointer]    -> all mice (incl. the laptop's
//                                         "mouse" touchpad surface)
//     [Libinput][Defaults][Touchpad]   -> all touchpads
//   with the key NaturalScroll=true. Explicit per-device sections
//   ([Libinput][vendor][product][name], written by System Settings) take
//   precedence over the defaults, so a user's per-device override is kept.
//
//   Plasma 5 (legacy, kded input plugin): the same intent with
//     [Mouse] / [Touchpad] sections and the key XLbInptNaturalScroll=true.
//   KWin 6 ignores those, but they are written too so the config stays
//   correct on a Plasma 5 host.
//
// Idempotent: only touches those keys and preserves everything else (the
// user's other input settings, per-device overrides).
//
// Run as: java NaturalScroll.java   (Java 25 compact source file)
import java.nio.file.*;
import java.util.*;

void main() throws Exception {
    var path = Path.of(System.getProperty("user.home"), ".config", "kcminputrc");
    var lines = new ArrayList<>(Files.exists(path) ? Files.readAllLines(path) : List.of());

    // Plasma 6 class defaults: [Mouse]/[Touchpad] of Plasma 5 are dead keys
    // there, the real defaults live under [Libinput][Defaults][...].
    ensure(lines, "[Libinput][Defaults][Pointer]", "NaturalScroll=true");
    ensure(lines, "[Libinput][Defaults][Touchpad]", "NaturalScroll=true");
    // Plasma 5 compatibility.
    ensure(lines, "[Mouse]", "XLbInptNaturalScroll=true");
    ensure(lines, "[Touchpad]", "XLbInptNaturalScroll=true");

    Files.createDirectories(path.getParent());
    Files.write(path, lines);
}

// Set key=value in the given [section], adding the section or the key line
// if missing; replace an existing key line. Preserves all other lines.
void ensure(List<String> lines, String section, String entry) {
    int idx = sectionIndex(lines, section);
    if (idx < 0) {
        lines.add(section);
        lines.add(entry);
        return;
    }
    String key = entry.substring(0, entry.indexOf('='));
    int j = idx + 1;
    while (j < lines.size() && !lines.get(j).isBlank() && !lines.get(j).stripLeading().startsWith("[")) {
        if (lines.get(j).stripLeading().startsWith(key + "=")) {
            lines.set(j, entry);
            return;
        }
        j++;
    }
    // Key not found: insert right after the section's last entry line.
    lines.add(j, entry);
}

int sectionIndex(List<String> lines, String section) {
    for (int i = 0; i < lines.size(); i++) {
        if (lines.get(i).strip().equals(section)) {
            return i;
        }
    }
    return -1;
}
