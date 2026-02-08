#!/usr/bin/env python3
import os
import sys
import time
from typing import List, Dict, Tuple

import requests


def env(name: str, default: str | None = None) -> str:
    val = os.getenv(name, default)
    if val is None or val == "":
        raise ValueError(f"Missing required env var: {name}")
    return val


QBIT_URL = env("QBIT_URL", "http://127.0.0.1:8080").rstrip("/")
QBIT_USER = env("QBIT_USER")
QBIT_PASS = env("QBIT_PASS")

FORCE_DAYS = float(env("FORCE_DAYS", "7"))
POLL_SECONDS = int(env("POLL_SECONDS", "900"))  # 15 minutes

# Comma-separated list of categories to manage (default: tv,movies)
CATEGORIES = [c.strip() for c in env("CATEGORIES", "tv,movies").split(",") if c.strip()]

# Optional: Only act on torrents whose tracker contains this substring (e.g. "torrentleech")
TRACKER_MATCH = os.getenv("TRACKER_MATCH", "").strip().lower()


def log(msg: str) -> None:
    print(time.strftime("%Y-%m-%d %H:%M:%S"), msg, flush=True)


def qb_login(session: requests.Session) -> None:
    r = session.post(
        f"{QBIT_URL}/api/v2/auth/login",
        data={"username": QBIT_USER, "password": QBIT_PASS},
        timeout=15,
    )
    # qBittorrent returns 200 with "Ok." on success, 403 on failure
    if r.status_code != 200 or "Ok" not in r.text:
        raise RuntimeError(f"qBittorrent login failed: {r.status_code} {r.text[:200]}")


def qb_torrents(session: requests.Session) -> List[Dict]:
    r = session.get(f"{QBIT_URL}/api/v2/torrents/info", timeout=30)
    r.raise_for_status()
    return r.json()


def qb_trackers(session: requests.Session, torrent_hash: str) -> List[Dict]:
    r = session.get(
        f"{QBIT_URL}/api/v2/torrents/trackers",
        params={"hash": torrent_hash},
        timeout=15,
    )
    r.raise_for_status()
    return r.json()


def qb_set_force(session: requests.Session, hashes: List[str], value: bool) -> None:
    if not hashes:
        return
    # qBittorrent expects hashes separated by '|'
    payload = {"hashes": "|".join(hashes), "value": "true" if value else "false"}
    r = session.post(f"{QBIT_URL}/api/v2/torrents/setForceStart", data=payload, timeout=30)
    r.raise_for_status()


def matches_tracker(session: requests.Session, t: Dict) -> bool:
    """Optional filter so we only touch torrents that match TRACKER_MATCH."""
    if not TRACKER_MATCH:
        return True
    th = t.get("hash")
    if not th:
        return False
    try:
        trackers = qb_trackers(session, th)
        for tr in trackers:
            url = (tr.get("url") or "").lower()
            if TRACKER_MATCH in url:
                return True
        return False
    except Exception as e:
        # If tracker lookup fails, be conservative and skip
        log(f"WARN: tracker lookup failed for {th[:8]}…; skipping. ({e})")
        return False


def compute_actions(session: requests.Session, torrents: List[Dict]) -> Tuple[List[str], List[str]]:
    now = int(time.time())
    force_hashes: List[str] = []
    unforce_hashes: List[str] = []

    for t in torrents:
        category = (t.get("category") or "").strip()
        if category not in CATEGORIES:
            continue

        # Only consider completed torrents
        completion_on = int(t.get("completion_on") or 0)
        progress = float(t.get("progress") or 0.0)
        if completion_on <= 0 or progress < 1.0:
            continue

        if not matches_tracker(session, t):
            continue

        age_days = (now - completion_on) / 86400.0
        is_forced = bool(t.get("force_start"))

        if age_days < FORCE_DAYS:
            if not is_forced:
                force_hashes.append(t["hash"])
        else:
            if is_forced:
                unforce_hashes.append(t["hash"])

    return force_hashes, unforce_hashes


def main() -> None:
    log(f"Starting qBit force-seed worker")
    log(f"QBIT_URL={QBIT_URL} FORCE_DAYS={FORCE_DAYS} POLL_SECONDS={POLL_SECONDS} CATEGORIES={CATEGORIES}")
    if TRACKER_MATCH:
        log(f"TRACKER_MATCH={TRACKER_MATCH}")

    session = requests.Session()

    while True:
        try:
            qb_login(session)
            torrents = qb_torrents(session)
            to_force, to_unforce = compute_actions(session, torrents)

            if to_force:
                log(f"Force-start ON for {len(to_force)} torrents (categories={CATEGORIES})")
                qb_set_force(session, to_force, True)

            if to_unforce:
                log(f"Force-start OFF for {len(to_unforce)} torrents (categories={CATEGORIES})")
                qb_set_force(session, to_unforce, False)

            if not to_force and not to_unforce:
                log("No changes needed.")

        except Exception as e:
            log(f"ERROR: {e}")

        time.sleep(POLL_SECONDS)


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        log("Exiting.")
        sys.exit(0)
