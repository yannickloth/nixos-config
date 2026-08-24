#!/usr/bin/env python3
"""Seed the kid-safety filter into the Open WebUI database.

Idempotent: inserts or updates a function row keyed by a fixed ID. Open WebUI
queries filters from the database at request time, so changes take effect
without restarting the service.

Usage: seed_gates.py /path/to/filter.py
"""

import json
import os
import sqlite3
import sys
import time

FILTER_ID = "5f3d8b7e-1c2d-4a9e-8f6a-2b3c4d5e6f70"
FILTER_NAME = "kid-safety"
DB_PATH = "/var/lib/open-webui/data/webui.db"
REQUIRED_COLUMNS = [
    "id", "user_id", "name", "type", "content", "meta", "valves",
    "is_active", "is_global", "updated_at", "created_at",
]


def wait_for_table(db_path, table, timeout=60):
    deadline = time.time() + timeout
    while time.time() < deadline:
        try:
            con = sqlite3.connect(db_path, timeout=5)
            found = con.execute(
                "SELECT 1 FROM sqlite_master WHERE type='table' AND name=?", (table,)
            ).fetchone()
            con.close()
            if found:
                return True
        except sqlite3.Error:
            pass
        time.sleep(2)
    return False


def main():
    if len(sys.argv) < 2 or not os.path.exists(sys.argv[1]):
        print("error: filter source file missing", file=sys.stderr)
        sys.exit(1)

    if not wait_for_table(DB_PATH, "function"):
        print(f"error: '{DB_PATH}' has no 'function' table yet", file=sys.stderr)
        sys.exit(1)

    with open(sys.argv[1]) as f:
        content = f.read()

    con = sqlite3.connect(DB_PATH, timeout=10)
    try:
        cols = [r[1] for r in con.execute("PRAGMA table_info(function)")]
        missing = [c for c in REQUIRED_COLUMNS if c not in cols]
        if missing:
            print(f"error: schema mismatch, missing columns: {missing}", file=sys.stderr)
            sys.exit(1)

        row = con.execute(
            "SELECT content FROM function WHERE id=?", (FILTER_ID,)
        ).fetchone()
        if row is not None and row[0] == content:
            print("kid-safety filter already up to date")
            return

        now = int(time.time())
        meta = json.dumps({"description": "Blocks kid-inappropriate subjects and swaps unsafe replies."})
        con.execute(
            """INSERT INTO function
                   (id, user_id, name, type, content, meta, valves,
                    is_active, is_global, updated_at, created_at)
               VALUES (?, NULL, ?, 'filter', ?, ?, NULL, 1, 1, ?, ?)
               ON CONFLICT(id) DO UPDATE SET
                   name=excluded.name, type=excluded.type, content=excluded.content,
                   meta=excluded.meta, is_active=1, is_global=1,
                   updated_at=excluded.updated_at""",
            (FILTER_ID, FILTER_NAME, content, meta, now, now),
        )
        con.commit()
        print("kid-safety filter seeded")
    finally:
        con.close()


if __name__ == "__main__":
    main()
