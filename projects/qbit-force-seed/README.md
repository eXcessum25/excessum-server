# qBittorrent Force-Seed Worker (Private Tracker Friendly)

This container automatically **force-seeds newly completed torrents for a fixed period** (default: 7 days), then **removes force-seeding afterwards**.

It exists to satisfy **private tracker hit-and-run (H&R) rules** (e.g. TorrentLeech), which typically require *continuous seeding time* immediately after download — something qBittorrent’s normal queueing does not guarantee.

---

## What problem this solves

qBittorrent’s queueing system is good for system stability, but many private trackers:

- Do **not** count queued torrents as seeding
- Expect **continuous seeding immediately after completion**
- Will issue **H&R warnings** if seeding is delayed or interrupted

This worker bridges that mismatch automatically.

---

## Behaviour (plain English)

On a fixed interval (default: every 15 minutes), the worker:

1. Connects to qBittorrent via the Web API
2. Looks at **completed torrents**
3. Filters to specific **categories** (default: `tv`, `movies`)
4. (Optional) Filters to a specific **tracker** (e.g. TorrentLeech)
5. Applies logic:
    - **If completed < N days ago** → `Force Start = ON`
    - **If completed ≥ N days ago** → `Force Start = OFF`

Result:
- New torrents seed continuously during the tracker’s H&R window
- Older torrents return to normal queue management
- No manual babysitting required

---

## What it does *not* do

- ❌ Does not change upload speeds
- ❌ Does not alter queue limits
- ❌ Does not force-seed everything forever
- ❌ Does not touch incomplete torrents
- ❌ Does not modify torrent data or files

It only toggles **Force Start**.

---

## Configuration

All configuration is via environment variables.

### Required
```env
QBIT_URL=http://127.0.0.1:8080
QBIT_USER=your_qbit_username
QBIT_PASS=your_qbit_password
