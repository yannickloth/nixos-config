// Seed the kid-safety filter into the Open WebUI database (idempotent).
//
// Inserts or updates the 'function' row keyed by a fixed ID. Open WebUI reads
// filters from the database at request time, so changes take effect without a
// restart.
//
// Run as: java --class-path <sqlite-jdbc.jar> seed_gates.java <filter.py>
import java.nio.file.*;
import java.sql.*;
import java.util.*;

String FILTER_ID = "5f3d8b7e-1c2d-4a9e-8f6a-2b3c4d5e6f70";
String FILTER_NAME = "kid-safety";
String DB_PATH = System.getenv().getOrDefault("OPEN_WEBUI_DB", "/var/lib/open-webui/data/webui.db");
List<String> REQUIRED_COLUMNS = List.of(
    "id", "user_id", "name", "type", "content", "meta", "valves",
    "is_active", "is_global", "updated_at", "created_at");

void main(String[] args) {
    if (args.length < 1 || !Files.exists(Path.of(args[0]))) {
        System.err.println("error: filter source file missing");
        System.exit(1);
    }

    if (!waitForTable()) {
        System.err.println("error: '" + DB_PATH + "' has no 'function' table yet");
        System.exit(1);
    }

    String content;
    try {
        content = Files.readString(Path.of(args[0]));
    } catch (Exception e) {
        System.err.println("error: cannot read filter source: " + e.getMessage());
        System.exit(1);
        return;
    }

    try (Connection con = DriverManager.getConnection("jdbc:sqlite:" + DB_PATH)) {
        con.setAutoCommit(false);

        var missing = new ArrayList<String>();
        try (var st = con.createStatement();
             var rs = st.executeQuery("PRAGMA table_info(function)")) {
            var cols = new ArrayList<String>();
            while (rs.next()) {
                cols.add(rs.getString(2));
            }
            for (var c : REQUIRED_COLUMNS) {
                if (!cols.contains(c)) {
                    missing.add(c);
                }
            }
        }
        if (!missing.isEmpty()) {
            System.err.println("error: schema mismatch, missing columns: " + missing);
            System.exit(1);
            return;
        }

        String existing = null;
        try (var ps = con.prepareStatement("SELECT content FROM function WHERE id=?")) {
            ps.setString(1, FILTER_ID);
            try (var rs = ps.executeQuery()) {
                if (rs.next()) {
                    existing = rs.getString(1);
                }
            }
        }
        if (existing != null && existing.equals(content)) {
            System.out.println("kid-safety filter already up to date");
            return;
        }

        long now = System.currentTimeMillis() / 1000;
        String meta = "{\"description\": \"Blocks kid-inappropriate subjects and swaps unsafe replies.\"}";
        try (var ps = con.prepareStatement(
                "INSERT INTO function (id, user_id, name, type, content, meta, valves, is_active, is_global, updated_at, created_at) " +
                "VALUES (?, NULL, ?, 'filter', ?, ?, NULL, 1, 1, ?, ?) " +
                "ON CONFLICT(id) DO UPDATE SET name=excluded.name, type=excluded.type, content=excluded.content, " +
                "meta=excluded.meta, is_active=1, is_global=1, updated_at=excluded.updated_at")) {
            ps.setString(1, FILTER_ID);
            ps.setString(2, FILTER_NAME);
            ps.setString(3, content);
            ps.setString(4, meta);
            ps.setLong(5, now);
            ps.setLong(6, now);
            ps.executeUpdate();
        }
        con.commit();
        System.out.println("kid-safety filter seeded");
    } catch (Exception e) {
        System.err.println("error: " + e.getMessage());
        System.exit(1);
    }
}

boolean waitForTable() {
    long deadline = System.currentTimeMillis() + 60_000;
    while (System.currentTimeMillis() < deadline) {
        try (Connection con = DriverManager.getConnection("jdbc:sqlite:" + DB_PATH)) {
            try (var st = con.createStatement();
                 var rs = st.executeQuery(
                     "SELECT 1 FROM sqlite_master WHERE type='table' AND name='function'")) {
                if (rs.next()) {
                    return true;
                }
            }
        } catch (Exception ignored) {
            // DB not ready yet (lock or not created); retry.
        }
        try {
            Thread.sleep(2000);
        } catch (InterruptedException e) {
            return false;
        }
    }
    return false;
}
