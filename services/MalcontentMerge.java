// Merge KConfig-style INI sections from a source file (the Nix-managed
// parental-control defaults) into a target file (the accountsservice per-user
// keyfile), so the Nix config and manual (malcontentctl) edits coexist:
//
//   - AppFilter app list: UNION of manual entries and Nix entries
//     (Nix removals cannot un-allow manually added apps — remove them manually).
//   - OarsFilter ratings map: per-key merge, Nix entries win on conflict.
//   - Other managed keys (filter on/off flag, Allow*Installation, SessionLimits):
//     Nix config is the source of truth.
//   - Everything else in the target (remembered Session, unknown keys/sections)
//     is preserved untouched.
//
// Idempotent. Run as: java MalcontentMerge.java <source> <target>
import java.nio.file.*;
import java.util.*;
import java.util.regex.*;

void main(String[] args) throws Exception {
    if (args.length < 2) {
        System.err.println("usage: malcontent-merge.java <source> <target>");
        System.exit(1);
    }
    var src = readIni(Path.of(args[0]));
    var dstPath = Path.of(args[1]);
    var dst = readIni(Files.exists(dstPath) ? dstPath : null);

    var appFilterSection = "com.endlessm.ParentalControls.AppFilter";
    for (var e : src.entrySet()) {
        var dsec = dst.computeIfAbsent(e.getKey(), k -> new LinkedHashMap<>());
        for (var kv : e.getValue().entrySet()) {
            if (e.getKey().equals(appFilterSection) && kv.getKey().equals("AppFilter")) {
                dsec.put(kv.getKey(), unionAppLists(dsec.get(kv.getKey()), kv.getValue()));
            } else if (e.getKey().equals(appFilterSection) && kv.getKey().equals("OarsFilter")) {
                dsec.put(kv.getKey(), unionOarsFilters(dsec.get(kv.getKey()), kv.getValue()));
            } else {
                dsec.put(kv.getKey(), kv.getValue());
            }
        }
    }

    var parent = dstPath.getParent();
    if (parent != null) {
        Files.createDirectories(parent);
    }
    Files.write(dstPath, renderIni(dst).getBytes());
}

// AppFilter values look like: (true, ['app.one', 'app.two'])
// Union the app-id lists; the enabled flag comes from src (Nix).
String unionAppLists(String dstVal, String srcVal) {
    if (dstVal == null || !dstVal.contains("[")) {
        return srcVal;
    }
    var flags = Pattern.compile("^\\s*\\((\\w+)").matcher(srcVal);
    String enabled = flags.find() ? flags.group(1) : "true";
    var ids = new LinkedHashSet<String>(extractQuoted(dstVal));
    ids.addAll(extractQuoted(srcVal));
    var items = String.join(", ", ids.stream().map(i -> "'" + i + "'").toList());
    return "(" + enabled + ", [" + items + "])";
}

// OarsFilter values look like: ('oars-1.1', {'section': 'level', ...})
// Merge the rating maps; src (Nix) wins per key. The schema string comes from src.
String unionOarsFilters(String dstVal, String srcVal) {
    if (dstVal == null || !dstVal.contains("{")) {
        return srcVal;
    }
    var schema = Pattern.compile("^\\s*\\('([^']*)'").matcher(srcVal);
    String schemaStr = schema.find() ? schema.group(1) : "oars-1.1";
    var merged = new LinkedHashMap<String, String>();
    var dstPairs = extractQuoted(block(dstVal, '{', '}'));
    for (int i = 0; i + 1 < dstPairs.size(); i += 2) {
        merged.put(dstPairs.get(i), dstPairs.get(i + 1));
    }
    var srcPairs = extractQuoted(block(srcVal, '{', '}'));
    for (int i = 0; i + 1 < srcPairs.size(); i += 2) {
        merged.put(srcPairs.get(i), srcPairs.get(i + 1));
    }
    var items = merged.entrySet().stream()
        .map(kv -> "'" + kv.getKey() + "': '" + kv.getValue() + "'")
        .reduce((a, b) -> a + ", " + b).orElse("");
    return "('" + schemaStr + "', {" + items + "})";
}

// All 'single-quoted' strings inside the first [...] block (AppFilter lists),
// or the whole string when there is no [...] (OarsFilter maps).
List<String> extractQuoted(String val) {
    var region = block(val, '[', ']');
    var m = Pattern.compile("'([^']*)'").matcher(region);
    var out = new ArrayList<String>();
    while (m.find()) {
        out.add(m.group(1));
    }
    return out;
}

// Substring between the first `open` and the last `close`, exclusive;
// the whole string when the block is absent.
String block(String val, char open, char close) {
    int o = val.indexOf(open);
    int c = val.lastIndexOf(close);
    return (o >= 0 && c > o) ? val.substring(o + 1, c) : val;
}

LinkedHashMap<String, LinkedHashMap<String, String>> readIni(Path p) throws Exception {
    var map = new LinkedHashMap<String, LinkedHashMap<String, String>>();
    if (p == null || !Files.exists(p)) {
        return map;
    }
    String cur = null;
    for (String line : Files.readAllLines(p)) {
        String s = line.strip();
        if (s.startsWith("[") && s.endsWith("]")) {
            cur = s.substring(1, s.length() - 1);
            map.putIfAbsent(cur, new LinkedHashMap<>());
        } else if (cur != null && !s.startsWith("#") && s.contains("=")) {
            int eq = s.indexOf('=');
            map.get(cur).put(s.substring(0, eq), s.substring(eq + 1));
        }
    }
    return map;
}

String renderIni(LinkedHashMap<String, LinkedHashMap<String, String>> map) {
    var sb = new StringBuilder();
    for (var e : map.entrySet()) {
        sb.append('[').append(e.getKey()).append("]\n");
        for (var kv : e.getValue().entrySet()) {
            sb.append(kv.getKey()).append('=').append(kv.getValue()).append('\n');
        }
        sb.append('\n');
    }
    return sb.toString();
}
