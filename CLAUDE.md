# CLAUDE.md

Guidance for AI assistants (Claude Code, Hermes) working in this repository.
Last audited against the running host: 2026-11-08.

## Project Overview

Docker Compose infrastructure for a single Ubuntu home server (`excessum`, LAN IP in `docker/.env`).
Main use: Jellyfin media + *arr automation. Also Immich (photos), Frigate (NVR) and Home Assistant
(HA is installed but has no real automations yet).

Privacy-sensitive download services route through NordVPN via Gluetun. LAN-facing services use
host networking so they stay reachable when the VPN is down.

## Commands

**Start / update all services** (pulls images, then `up -d --remove-orphans`):
```bash
./run.sh
```
**Stop all services:** `./stop.sh`

**Status** (always pass the same env files and -f list as `run.sh`):
```bash
cd docker && docker compose --env-file .env --env-file .env.secrets \
  -f docker-compose.vpn.yml -f docker-compose.ha.yml -f docker-compose.downloads.yml \
  -f docker-compose.mediaserver.yml -f docker-compose.admin.yml -f docker-compose.immich.yml \
  -f docker-compose.frigate.yml -f docker-compose.caddy.yml ps
```
If you add a compose file, update BOTH `run.sh` and `stop.sh`.

**Bootstrap a fresh Ubuntu server** (as root, in order):
`ubuntu-bootstrap/` 00-ubuntu, 01-ufw, 02-storage, 03-docker, 04-restic, 05-tailscale, 10-ssh-hardening (last).

## Compose files

| File | Contents |
|------|----------|
| `docker-compose.vpn.yml` | `vpn` bridge network + Gluetun (NordVPN, currently OpenVPN) |
| `docker-compose.downloads.yml` | qBittorrent, Sonarr, Radarr, Prowlarr, Bazarr, Recyclarr, Unpackerr (all via Gluetun); qbit-force-seed (host net) |
| `docker-compose.mediaserver.yml` | Jellyfin, Jellyseerr (host net); Tuliprox (via Gluetun) |
| `docker-compose.ha.yml` | Home Assistant (host), Zigbee2MQTT, Mosquitto |
| `docker-compose.admin.yml` | Portainer, Netdata, Dozzle, Filebrowser, ntfy, Healthchecks, hc-heartbeat (via Gluetun) |
| `docker-compose.immich.yml` | Immich server, machine-learning, Redis (valkey), Postgres |
| `docker-compose.frigate.yml` | Frigate NVR (host net) |
| `docker-compose.caddy.yml` | Caddy reverse proxy with Tailscale HTTPS certs |

Plex, Overseerr, Tautulli and Emby have been removed (replaced by Jellyfin/Jellyseerr).

## Network design

- **Via Gluetun** (`network_mode: "service:gluetun"`): qBittorrent, Sonarr, Radarr, Prowlarr, Bazarr,
  Recyclarr, Unpackerr, Tuliprox, hc-heartbeat. Their ports are published on the `gluetun` service.
  Gluetun has a healthcheck and a firewall kill-switch.
- **Known failure mode:** when Gluetun restarts/recreates, containers sharing its namespace lose
  networking and must be restarted too. (`depends_on: service_healthy` only helps at startup.)
- **Host network:** Jellyfin, Jellyseerr, Home Assistant, Frigate, Caddy, Portainer, Netdata, Dozzle, qbit-force-seed.
- hc-heartbeat pings Healthchecks from inside the VPN namespace, so a missing ping indicates VPN trouble.

## Storage

```
/                      ubuntu-vg LV, ~231G  (Docker, this repo + app configs)
/srv/storage/disks/das1, das2   physical data disks (~13T each)
/srv/storage/media     mergerfs pool of das1+das2 (movies, tv, tv-uk, personal, backups)
/srv/storage/downloads dedicated disk (qBittorrent)
/srv/storage/cctv      dedicated disk (Frigate)
```
App configs live in `docker/config/<service>` (git-ignored except recyclarr.yml).

## Configuration

| File | Contents | In git? |
|------|----------|---------|
| `docker/.env` | Paths, ports, TZ, VPN country, PUID/PGID, image versions | Yes |
| `docker/.env.secrets` | VPN credentials, DB passwords etc. | No (`.env.secrets.example` is the template) |

All services run as PUID:PGID 1000:1000 unless the image requires otherwise.

## Backups

`projects/restic-backup/` runs daily at 05:00 (`/etc/cron.d/restic-backup`) and snapshots this directory to
`/srv/storage/media/backups/server` (unencrypted restic repo, 7 daily / 4 weekly / 6 monthly).
**Limitations:** the repo is on the same mergerfs pool as the media (not offsite); the Immich DB and
Immich uploads are NOT covered by this job.

## Custom projects

- `projects/qbit-force-seed/` — polls qBittorrent and force-seeds completed torrents for N days (H&R rules).
- `projects/restic-backup/` — see above.

## Conventions

- **No `env_file:` in compose services.** Pass variables via explicit `environment:` blocks.
- **No hardcoded config in compose files.** Ports, paths, credentials come from `${VAR}` in `.env`/`.env.secrets`.
  Container-internal constants (e.g. `FIREWALL=on`) are fine.
- Prefer pinned image versions (see `TULIPROX_VERSION`); many images still use `:latest` — pin when touching them.
- Never commit `.env.secrets`, `*.key`, `*.crt`.

## Notes for Hermes (home server assistant)

- Hermes runs as user `hermes` with restricted access: Docker via a filtered proxy, logs via `hermes-docker-logs <name>`.
- Git needs `safe.directory` for this repo (ownership differs from the hermes user).
- Prefer read-only investigation first; propose changes to compose/.env as diffs for Alan to approve.
- Don't commit or run `./run.sh` without Alan's say-so.
