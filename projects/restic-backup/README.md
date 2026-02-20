# restic-backup

Daily backup of `/srv/excessum-server` to local storage using [restic](https://restic.net/).

## What gets backed up

Everything in `/srv/excessum-server/` except:

- `.git/`, `.idea/`, `.claude/` — VCS and IDE artefacts
- Log files and log databases (`*/logs/`, `*/log/`, `*.log`, `logs.db`)
- Application caches (`*/cache/`, `*/.cache/`, recyclarr's downloaded git repos)
- Auto-regenerated media covers — Sonarr/Radarr `MediaCover/` dirs (rebuilt on startup)
- Bulk Plex directories — Cache, Codecs, PhotoTranscoder, Media (all regeneratable);
  only the Plex SQLite databases are kept
- Runtime lock files (`.ha_run.lock`, qBittorrent `lockfile`)

The primary goals are:

1. **`docker/.env.secrets`** — VPN credentials, Plex claim token, qBittorrent password.
   Not in git. Would be painful to recreate from scratch.
2. **Application configs and databases** — Sonarr, Radarr, Prowlarr, Bazarr, qBittorrent,
   Home Assistant (including `.storage/`), Zigbee2MQTT (including coordinator backup),
   Mosquitto, Plex library databases, Overseerr, Tautulli, Portainer, Filebrowser.

## What is NOT backed up by this script

- **Immich database** — stored at `/srv/storage/immich-db` (outside this repo).
  Consider a separate backup strategy for that (e.g. `pg_dump` + restic).
- **Media files** — `/srv/storage/media/` (movies, TV, photos). These are large and
  generally re-downloadable; back them up separately if needed.
- **qBittorrent downloads** — `/srv/storage/downloads/`. Torrent files can be re-added.

## Destination

```
/srv/storage/media/backups/server
```

The restic repo is unencrypted (`--insecure-no-password`). This is a local backup on private hardware — no password to forget, no friction when recovering from a disaster.

## Retention policy

| Period  | Snapshots kept |
|---------|---------------|
| Daily   | 7             |
| Weekly  | 4             |
| Monthly | 6             |

Old snapshots are pruned automatically after each run.

## Setup

Run the bootstrap script once (as root):

```bash
sudo ubuntu-bootstrap/04-restic.sh
```

This will:
- Install the latest restic binary
- Copy `backup.sh` to `/usr/local/bin/restic-backup`
- Copy `excludes.txt` to `/etc/restic/excludes.txt`
- Initialise the restic repo (unencrypted)
- Install a daily cron job at 05:00

## Manual usage

```bash
# Run a backup immediately
sudo restic-backup

# List snapshots
sudo restic -r /srv/storage/media/backups/server --insecure-no-password snapshots

# Browse the latest snapshot
sudo restic -r /srv/storage/media/backups/server --insecure-no-password ls latest

# Restore a specific path from the latest snapshot
sudo restic -r /srv/storage/media/backups/server --insecure-no-password restore latest \
  --target /tmp/restore \
  --include /srv/excessum-server/docker/.env.secrets

# Check repo integrity
sudo restic -r /srv/storage/media/backups/server --insecure-no-password check
```

All commands require `--insecure-no-password` since the repo has no encryption.

## Logs

Cron output is appended to `/var/log/restic-backup.log`.
