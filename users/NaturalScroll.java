// Natural (inverse) scrolling for all mice and touchpads.
//
// Sets XLbInptNaturalScroll=true in the [Mouse] and [Touchpad] sections of
// KDE's ~/.config/kcminputrc. Idempotent: only touches those two keys and
// preserves everything else (the user's other input settings).
//
// Run as: java natural-scroll.java   (Java 25 compact source file)
import java.nio.file.*;
import java.util.*;

void main() throws Exception {
    var path = Path.of(System.getProperty("user.home"), ".config", "kcminputrc");
    var lines = new ArrayList<>(Files.exists(path) ? Files.readAllLines(path) : List.of());

    for (String section : List.of("[Mouse]", "[Touchpad]")) {
        int idx = sectionIndex(lines, section);
        if (idx < 0) {
            lines.add(section);
            lines.add("XLbInptNaturalScroll=true");
            continue;
        }
        int j = idx + 1;
        while (j < lines.size() && !lines.get(j).isBlank() && !lines.get(j).stripLeading().startsWith("[")) {
            if (lines.get(j).stripLeading().startsWith("XLbInptNaturalScroll=")) {
                lines.set(j, "XLbInptNaturalScroll=true");
                break;
            }
            j++;
        }
        if (j >= lines.size() || lines.get(j).isBlank() || lines.get(j).stripLeading().startsWith("[")) {
            lines.add(j, "XLbInptNaturalScroll=true");
        }
    }

    Files.createDirectories(path.getParent());
    Files.write(path, lines);
}

int sectionIndex(List<String> lines, String section) {
    for (int i = 0; i < lines.size(); i++) {
        if (lines.get(i).strip().equals(section)) {
            return i;
        }
    }
    return -1;
}
