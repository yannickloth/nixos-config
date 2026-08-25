// Merge KConfig-style INI sections from a source file into a target file,
// preserving the target's existing sections and keys (accountsservice per-user
// state such as the remembered Session). Idempotent.
//
// Run as: java malcontent-merge.java <source> <target>
import java.nio.file.*;
import java.util.*;

void main(String[] args) throws Exception {
    if (args.length < 2) {
        System.err.println("usage: malcontent-merge.java <source> <target>");
        System.exit(1);
    }
    var src = readIni(Path.of(args[0]));
    var dstPath = Path.of(args[1]);
    var dst = readIni(Files.exists(dstPath) ? dstPath : null);

    for (var e : src.entrySet()) {
        dst.computeIfAbsent(e.getKey(), k -> new LinkedHashMap<>()).putAll(e.getValue());
    }

    Files.createDirectories(dstPath.getParent());
    Files.write(dstPath, renderIni(dst).getBytes());
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
