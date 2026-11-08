#!/usr/bin/env python3
"""Read-only health check for the excessum home server.

Focus: things that work and can silently stop working.
  1. Gluetun / VPN (and containers riding on it)
  2. qBittorrent download disk space
  3. Sonarr / Radarr / Prowlarr losing indexers / download clients
  4. Containers down/unhealthy, and restic backups going stale

Prints a short report. Exit 0 = all fine, 1 = needs attention. Never modifies anything.
"""
import glob
import json
import re
import shutil
import subprocess
import sys
import os
import urllib.request
from datetime import datetime, timedelta, timezone

CONFIG = "/srv/excessum-server/docker/config"
ARRS = {  # name: (port, api version)
    "sonarr": (8989, "v3"),
    "radarr": (7878, "v3"),
    "prowlarr": (9696, "v1"),
}
# Health messages that are not worth waking anyone for.
ARR_IGNORE = re.compile(r"new update is available", re.I)

DISKS = {  # path: (min free GB, max used %)
    "/srv/storage/downloads": (100, 90),
    "/srv/storage/media": (300, 95),
    "/": (20, 90),
}
BACKUP_LOG = "/var/log/restic-backup.log"
BACKUP_MAX_AGE_H = 30
QBIT_DIR = "/srv/storage/downloads/qbittorrent"
QBIT_IDLE_DAYS = 4  # no new/updated download file for this long => something is wrong
GLUETUN_FLAP_LIMIT = 3  # VPN (re)connections in 24h before we call it flapping

os.environ.setdefault("DOCKER_HOST", "tcp://127.0.0.1:2375")

problems, notes = [], []


def run(cmd, timeout=60):
    try:
        r = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
        return r.returncode, r.stdout + r.stderr
    except Exception as e:  # noqa
        return 1, str(e)


def utc(ts):
    """Parse the RFC3339 prefix of a docker log line (nanosecond precision) as UTC."""
    return datetime.fromisoformat(ts.strip().split(".")[0].rstrip("Z") + "+00:00")


def recent_lines(container, hours=24):
    rc, log = run(["hermes-docker-logs", container], timeout=90)
    cutoff = datetime.now(timezone.utc) - timedelta(hours=hours)
    for line in log.splitlines():
        try:
            t = utc(line[:30])
        except Exception:  # noqa
            continue
        if t >= cutoff:
            yield line[31:]


# ---------------------------------------------------------------- containers
def check_containers():
    rc, out = run(["docker", "ps", "-a", "--format", "{{json .}}"])
    if rc != 0:
        problems.append(f"docker ps failed: {out.strip()[:200]}")
        return
    rows = [json.loads(l) for l in out.splitlines() if l.strip()]
    for c in rows:
        name, state, status = c["Names"], c["State"], c["Status"]
        if state != "running":
            problems.append(f"container {name} is {state} ({status})")
        elif "unhealthy" in status:
            problems.append(f"container {name} is UNHEALTHY ({status})")
        elif "Restarting" in status:
            problems.append(f"container {name} is restart-looping")
    notes.append(f"{sum(c['State'] == 'running' for c in rows)}/{len(rows)} containers running")


# -------------------------------------------------------------------- gluetun
UNIT = {"second": 1, "minute": 60, "hour": 3600, "day": 86400, "week": 604800, "month": 2592000, "year": 31536000}


def uptime_s(status):
    """'Up 8 days (healthy)' -> approx seconds (docker only gives coarse units)."""
    m = re.match(r"Up (About an?|Less than a|\d+) (\w+?)s?\b", status)
    if not m:
        return 0
    n = 1 if not m.group(1).isdigit() else int(m.group(1))
    return n * UNIT.get(m.group(2), 0)


def gluetun_dependents():
    """Containers whose compose service uses network_mode service:gluetun."""
    names = []
    for f in glob.glob("/srv/excessum-server/docker/docker-compose.*.yml"):
        cur = None
        for line in open(f):
            m = re.match(r"\s+container_name:\s*(\S+)", line)
            if m:
                cur = m.group(1)
            if re.search(r"network_mode:\s*[\"']?service:gluetun", line) and cur:
                names.append(cur)
    return names


def check_gluetun():
    rc, out = run(["docker", "ps", "--format", "{{json .}}"])
    ps = {json.loads(l)["Names"]: json.loads(l)["Status"] for l in out.splitlines() if l.strip()}
    gs = ps.get("gluetun")
    if gs is None:
        problems.append("gluetun is not running")
        return
    health = "healthy" if "(healthy)" in gs else ("starting" if "starting" in gs else "unhealthy")
    if health != "healthy":
        problems.append(f"gluetun health is '{health}' ({gs})")
    # A dependent that has been up much longer than gluetun holds a stale network namespace
    # (docker ps only gives coarse uptime, so allow one unit of slack).
    g_up = uptime_s(gs)
    stale = [n for n in gluetun_dependents() if n in ps and uptime_s(ps[n]) > g_up * 1.5 + 3600]
    if stale:
        problems.append("up much longer than gluetun (stale network?): " + ", ".join(stale))

    auth_fail = connects = 0
    for line in recent_lines("gluetun"):
        if "AUTH_FAILED" in line:
            auth_fail += 1
        if "Initialization Sequence Completed" in line or "Wireguard setup is complete" in line:
            connects += 1
    if auth_fail:
        problems.append(f"gluetun: {auth_fail} AUTH_FAILED in last 24h (NordVPN login rejected)")
    if connects > GLUETUN_FLAP_LIMIT:
        problems.append(f"gluetun: reconnected {connects} times in 24h (flapping)")
    notes.append(f"gluetun {health}, {connects} connect(s)/24h")


def check_mounts():
    """Every real filesystem in /etc/fstab must be mounted, and no formatted disk may sit unmounted.

    A data disk silently missing makes mergerfs/Sonarr see a smaller library (files 'vanish').
    """
    with open("/proc/mounts") as f:
        mounted = {l.split()[1] for l in f}
    missing = []
    with open("/etc/fstab") as f:
        for line in f:
            parts = line.split()
            if len(parts) >= 3 and not line.lstrip().startswith("#") and parts[2] in ("ext4", "xfs", "btrfs", "fuse.mergerfs"):
                if parts[1] not in mounted:
                    missing.append(parts[1])
    if missing:
        problems.append("fstab filesystems NOT mounted: " + ", ".join(missing))
    rc, out = run(["lsblk", "-rno", "NAME,FSTYPE,MOUNTPOINT,SIZE", "-b"])
    for l in out.splitlines():
        p = l.split()
        if len(p) == 3 and p[1] in ("ext4", "xfs", "btrfs") and int(p[2]) > 500e9:  # fs, no mountpoint, big
            problems.append(f"large disk /dev/{p[0]} ({int(p[2]) / 1e12:.1f} TB, {p[1]}) is not mounted")
    if not missing:
        notes.append("all fstab filesystems mounted")


# ----------------------------------------------------------------------- disks
def check_disks():
    for path, (min_free_gb, max_pct) in DISKS.items():
        try:
            u = shutil.disk_usage(path)
        except Exception as e:  # noqa
            problems.append(f"disk {path}: {e}")
            continue
        pct, free_gb = u.used / u.total * 100, u.free / 1e9
        line = f"{path}: {pct:.0f}% used, {free_gb:.0f} GB free"
        if pct >= max_pct or free_gb < min_free_gb:
            problems.append("LOW DISK " + line)
        else:
            notes.append(line)


def check_qbit_logs():
    # qBittorrent's API needs a login we do not have; look for disk errors in its own log instead.
    pat = re.compile(r"no space left|disk full|not enough (disk )?space|I/O error|Disk write error", re.I)
    hits = [l for l in recent_lines("qbittorrent") if pat.search(l)]
    if hits:
        problems.append(f"qbittorrent: {len(hits)} disk error line(s) in 24h, e.g. {hits[-1][:160]}")


def check_qbit_activity():
    """Belt and braces: has qBittorrent written any download data recently?

    Uses file mtimes (incl. in-progress .!qB files), ignoring logs, because the API needs a login.
    Silence for days means the VPN, indexers, *arr -> qbit hand-off or qbit itself is broken.
    """
    newest, newest_path = 0.0, ""
    for root, _dirs, files in os.walk(QBIT_DIR):
        for f in files:
            if f.endswith(".log"):
                continue
            fp = os.path.join(root, f)
            try:
                t = os.stat(fp).st_mtime
            except OSError:
                continue
            if t > newest:
                newest, newest_path = t, fp
    if not newest:
        problems.append(f"qbittorrent: no download files found under {QBIT_DIR}")
        return
    age = datetime.now().timestamp() - newest
    days = age / 86400
    what = os.path.relpath(newest_path, QBIT_DIR).split(os.sep)[0][:60]
    if days > QBIT_IDLE_DAYS:
        problems.append(f"qbittorrent: nothing downloaded for {days:.1f} days (last: {what})")
    else:
        notes.append(f"qbit last download {days * 24:.0f}h ago" if days < 3 else f"qbit last download {days:.1f}d ago")


# ------------------------------------------------------------- *arr health
def api_key(name):
    with open(f"{CONFIG}/{name}/config.xml") as f:
        m = re.search(r"<ApiKey>([^<]+)</ApiKey>", f.read())
    return m.group(1) if m else None


def api(name, path):
    port, ver = ARRS[name]
    req = urllib.request.Request(f"http://localhost:{port}/api/{ver}/{path}", headers={"X-Api-Key": api_key(name) or ""})
    with urllib.request.urlopen(req, timeout=15) as r:
        return json.load(r)


def check_arrs():
    for name in ARRS:
        try:
            health = api(name, "health")
        except Exception as e:  # noqa
            problems.append(f"{name}: API unreachable ({e})")
            continue
        real = [h for h in health if not ARR_IGNORE.search(h.get("message", ""))]
        for h in real:
            problems.append(f"{name} {h['type']}: {h['message'][:160]}")
        # Explicit status endpoints: catch failures that health might not surface yet.
        for ep, label in (("indexerstatus", "indexer"), ("downloadclientstatus", "download client")):
            if name == "prowlarr" and ep == "downloadclientstatus":
                continue
            try:
                for s in api(name, ep):
                    if s.get("disabledTill"):
                        problems.append(f"{name}: {label} disabled until {s['disabledTill']}")
            except Exception:  # noqa
                pass
        if name == "prowlarr":
            try:
                idx = api(name, "indexer")
                off = [i["name"] for i in idx if not i["enable"]]
                if off:
                    problems.append("prowlarr: indexers disabled: " + ", ".join(off))
                notes.append(f"prowlarr {len(idx) - len(off)}/{len(idx)} indexers enabled")
            except Exception:  # noqa
                pass
        if not real:
            notes.append(f"{name} health OK")


# --------------------------------------------------------------------- backup
def check_backup():
    try:
        with open(BACKUP_LOG, errors="replace") as f:
            text = f.read()
    except Exception as e:  # noqa
        problems.append(f"cannot read {BACKUP_LOG}: {e}")
        return
    started = re.findall(r"^(\d{4}-\d\d-\d\d \d\d:\d\d:\d\d) \[INFO\] Starting restic", text, re.M)
    done = re.findall(r"^(\d{4}-\d\d-\d\d \d\d:\d\d:\d\d) \[INFO\] Done\.", text, re.M)
    if not done:
        problems.append("restic: no completed backup found in log")
        return
    age_h = (datetime.now() - datetime.strptime(done[-1], "%Y-%m-%d %H:%M:%S")).total_seconds() / 3600
    if age_h > BACKUP_MAX_AGE_H:
        problems.append(f"restic: last completed backup was {age_h:.0f}h ago ({done[-1]})")
    elif started and started[-1] > done[-1]:
        problems.append(f"restic: backup started {started[-1]} but did not complete")
    else:
        notes.append(f"restic OK ({age_h:.0f}h ago)")


def main():
    for fn in (check_containers, check_mounts, check_gluetun, check_disks, check_qbit_logs, check_qbit_activity, check_arrs, check_backup):
        try:
            fn()
        except Exception as e:  # noqa
            problems.append(f"{fn.__name__} crashed: {e!r}")
    if problems:
        print("ATTENTION NEEDED")
        for p in problems:
            print(f"- {p}")
    else:
        print("All fine")
    print("\nDetails: " + "; ".join(notes))
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
