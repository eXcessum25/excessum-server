#!/usr/bin/env python3
"""Taste profile store for TV suggestions (ratings seeded from the Sonarr library).

Usage:
  taste.py init            load/refresh series from Sonarr into the DB (keeps ratings)
  taste.py next [N]        print the next N unrated series (queue order) as JSON
  taste.py rate TVDB_OR_TITLE R [note]   R in loved|ok|disliked|unseen (title may end in % for groups)
  taste.py stats           counts per rating
  taste.py dump            all rated series as JSON

DB lives outside the repo: ~/.hermes/data/tv-taste.db
"""
import json
import os
import re
import sqlite3
import sys
import urllib.request

DB = os.path.expanduser("~/.hermes/data/tv-taste.db")
SONARR = "http://localhost:8989/api/v3/series"
KEYFILE = "/srv/excessum-server/docker/config/sonarr/config.xml"
RATINGS = {"loved", "ok", "disliked", "unseen"}


def db():
    os.makedirs(os.path.dirname(DB), exist_ok=True)
    c = sqlite3.connect(DB)
    c.row_factory = sqlite3.Row
    c.execute("""CREATE TABLE IF NOT EXISTS series (
        tvdb_id INTEGER PRIMARY KEY, tmdb_id INTEGER, title TEXT, year INTEGER, genres TEXT,
        network TEXT, status TEXT, overview TEXT, added TEXT, rating TEXT, note TEXT, rated_at TEXT)""")
    return c


def cmd_init():
    m = re.search(r"<ApiKey>([^<]+)</ApiKey>", open(KEYFILE).read())
    assert m, "no Sonarr ApiKey found"
    key = m.group(1)
    req = urllib.request.Request(SONARR, headers={"X-Api-Key": key})
    series = json.load(urllib.request.urlopen(req, timeout=30))
    c = db()
    for s in series:
        c.execute("""INSERT INTO series (tvdb_id,tmdb_id,title,year,genres,network,status,overview,added)
                     VALUES (?,?,?,?,?,?,?,?,?)
                     ON CONFLICT(tvdb_id) DO UPDATE SET title=excluded.title, status=excluded.status,
                       genres=excluded.genres, overview=excluded.overview""",
                  (s.get("tvdbId"), s.get("tmdbId"), s["title"], s.get("year"), ",".join(s.get("genres", [])),
                   s.get("network", ""), s.get("status", ""), (s.get("overview") or "")[:400], s["added"][:10]))
    c.commit()
    print(f"{len(series)} series synced")


def cmd_next(n=1):
    # Queue order: deliberate adds (after the Feb-2026 bulk import) newest first, then the bulk set by first-air year, newest first.
    rows = db().execute("""SELECT * FROM series WHERE rating IS NULL
        ORDER BY (added >= '2026-03-01') DESC, CASE WHEN added >= '2026-03-01' THEN added END DESC, year DESC, title
        LIMIT ?""", (n,)).fetchall()
    print(json.dumps([dict(r) for r in rows], indent=1))


def cmd_rate(tvdb, r, note=""):
    assert r in RATINGS, f"rating must be one of {RATINGS}"
    c = db()
    # Accept a tvdb id, or a title (exact, case-insensitive; "prefix%" for groups like "Louis Theroux%").
    if str(tvdb).isdigit():
        where, arg = "tvdb_id=?", int(tvdb)
    else:
        where, arg = "title LIKE ?", tvdb
    cur = c.execute(f"UPDATE series SET rating=?, note=?, rated_at=datetime('now') WHERE {where}", (r, note, arg))
    c.commit()
    print("ok" if cur.rowcount else "no such series")


def cmd_stats():
    c = db()
    for r in c.execute("SELECT COALESCE(rating,'(unrated)') r, COUNT(*) n FROM series GROUP BY r ORDER BY n DESC"):
        print(f"{r['r']}: {r['n']}")


def cmd_dump():
    print(json.dumps([dict(r) for r in db().execute("SELECT * FROM series WHERE rating IS NOT NULL")], indent=1))


if __name__ == "__main__":
    a = sys.argv[1:]
    {"init": cmd_init, "stats": cmd_stats, "dump": cmd_dump}.get(a[0] if a else "", lambda: None)() if (a and a[0] in ("init", "stats", "dump")) \
        else cmd_next(int(a[1]) if len(a) > 1 else 1) if a and a[0] == "next" \
        else cmd_rate(*a[1:]) if a and a[0] == "rate" else print(__doc__)
