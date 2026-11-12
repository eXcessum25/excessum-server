#!/usr/bin/env python3
"""Backfill Jellyfin 'watched' state in batches of 10 series, driven from chat.

  jf_watched.py batch            print the next 10 candidates (numbered) and remember them as the current batch
  jf_watched.py mark 1 3 5       mark those numbers of the current batch as watched (whole series) in Jellyfin
  jf_watched.py mark none        mark nothing; skip batch
  jf_watched.py status           counts

Candidates: Jellyfin series not already played, ordered by Alan's taste ratings (loved, then ok, then unrated A-Z).
Series rated 'unseen' or 'disliked' are excluded. State: ~/.hermes/data/jf-watched.json (shown/decided lists).
Jellyfin key: JELLYFIN_API_KEY in ~/.hermes/.env. Marking a series played marks all its episodes.
"""
import json, os, sqlite3, sys, urllib.request

HOME = os.path.expanduser("~/.hermes")
STATE = f"{HOME}/data/jf-watched.json"
JF = "http://localhost:8096"
key = [l.split("=", 1)[1].strip() for l in open(f"{HOME}/.env") if l.startswith("JELLYFIN_API_KEY=")][0]
H = {"Authorization": f'MediaBrowser Token="{key}"'}


def req(method, path):
    return urllib.request.urlopen(urllib.request.Request(JF + path, headers=H, method=method, data=b"" if method == "POST" else None), timeout=120)


def get(path):
    return json.load(req("GET", path))


def state():
    if os.path.exists(STATE):
        return json.load(open(STATE))
    return {"current": [], "decided": {}}


def save(s):
    json.dump(s, open(STATE, "w"), indent=1)


def uid():
    return next(u["Id"] for u in get("/Users") if u["Name"] == "newteh")


def candidates(s):
    u = uid()
    items = get(f"/Users/{u}/Items?IncludeItemTypes=Series&Recursive=true&Fields=ProviderIds&Limit=2000")["Items"]
    db = sqlite3.connect(f"{HOME}/data/tv-taste.db")
    rt = {r[0]: r[1] for r in db.execute("select tvdb_id, rating from series where rating is not null")}
    out = []
    for i in items:
        if i["UserData"].get("Played") or i["Id"] in s["decided"]:
            continue
        rating = rt.get(int(i["ProviderIds"].get("Tvdb", 0) or 0))
        if rating in ("unseen", "disliked"):
            continue
        out.append((0 if rating == "loved" else 1 if rating == "ok" else 2, i["Name"].lower(), i["Name"], i["Id"], i.get("ProductionYear"), rating))
    out.sort()
    return out


def cmd_batch():
    s = state()
    c = candidates(s)[:10]
    s["current"] = [{"n": n, "id": x[3], "name": x[2], "year": x[4]} for n, x in enumerate(c, 1)]
    save(s)
    for e, x in zip(s["current"], c):
        tag = {"loved": " (you rated: loved)", "ok": " (you rated: ok)"}.get(x[5], "")
        print(f"{e['n']}. {e['name']} ({e['year']}){tag}")
    print(f"[{len(candidates(s))} candidates remain]")


def cmd_mark(args):
    s = state()
    cur = {e["n"]: e for e in s["current"]}
    nums = [] if args == ["none"] else [int(a) for a in args]
    bad = [n for n in nums if n not in cur]
    if bad:
        print("not in current batch:", bad)
        return
    u = uid()
    for n in nums:
        req("POST", f"/Users/{u}/PlayedItems/{cur[n]['id']}")
        print("marked watched:", cur[n]["name"])
    for e in s["current"]:  # every shown item is decided, watched or not, so it is not asked again
        s["decided"][e["id"]] = "watched" if e["n"] in nums else "not-watched"
    s["current"] = []
    save(s)
    print(f"decided so far: {len(s['decided'])} ({sum(v == 'watched' for v in s['decided'].values())} watched)")


def cmd_status():
    s = state()
    print(f"decided {len(s['decided'])}, watched {sum(v == 'watched' for v in s['decided'].values())}, remaining candidates {len(candidates(s))}")


if __name__ == "__main__":
    a = sys.argv[1:]
    if a[:1] == ["batch"]:
        cmd_batch()
    elif a[:1] == ["mark"] and len(a) > 1:
        cmd_mark(a[1:])
    elif a[:1] == ["status"]:
        cmd_status()
    else:
        print(__doc__)
