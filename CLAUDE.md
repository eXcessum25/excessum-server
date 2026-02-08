# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Docker Compose infrastructure for a home media and home automation stack. Uses a VPN-first architecture where privacy-sensitive download services route through NordVPN via Gluetun, while LAN-facing services (Plex, Home Assistant) remain accessible during VPN outages.

## Commands

**Start all services:**
```bash
./run.sh
```

**Stop all services:**
```bash
./stop.sh
```

**Check container health:**
```bash
cd docker && docker compose \
  -f docker-compose.vpn.yml \
  -f docker-compose.ha.yml \
  -f docker-compose.plex.yml \
  -f docker-compose.downloads.yml \
  -f docker-compose.admin.yml \
  ps
```

**Bootstrap a fresh Ubuntu server** (run scripts in order as root):
```bash
ubuntu-bootstrap/00-ubuntu.sh   # Base packages, mergerfs
ubuntu-bootstrap/01-ufw.sh      # Firewall
ubuntu-bootstrap/02-storage.sh  # Disk mounts & mergerfs pool
ubuntu-bootstrap/03-docker.sh   # Docker Engine
ubuntu-bootstrap/10-ssh-hardening.sh  # SSH lockdown (last, after key setup)
```

## Architecture

### Compose File Structure

Five compose files, all loaded together by `run.sh` and `stop.sh`:

| File | Purpose |
|------|---------|
| `docker/docker-compose.vpn.yml` | `vpn` bridge network + Gluetun VPN gateway |
| `docker/docker-compose.downloads.yml` | VPN-routed download services (qBittorrent, Sonarr, Radarr, Prowlarr, Bazarr, qbit-force-seed) |
| `docker/docker-compose.plex.yml` | LAN-facing media (Plex, Overseerr, Tautulli) |
| `docker/docker-compose.ha.yml` | Home automation (Home Assistant, Zigbee2MQTT, Mosquitto) |
| `docker/docker-compose.admin.yml` | Admin/monitoring (Portainer, Netdata) |

### Network Design

- **VPN-routed services** use `network_mode: "service:gluetun"` to share the VPN gateway's network namespace. Gluetun exposes ports for all of them and has a healthcheck; downstream services use `depends_on: condition: service_healthy`.
- **LAN-facing services** use `network_mode: host` for direct LAN access (Plex needs it for streaming, Home Assistant for mDNS/SSDP discovery).
- Gluetun's built-in firewall with kill-switch prevents traffic leaks if VPN drops.

### Service Groups

**VPN-routed (via Gluetun):** qBittorrent (8085), Prowlarr (9696), Sonarr (8989), Bazarr (6767)

**LAN-facing (host network):** Plex (32400), Overseerr, Tautulli (8181), Home Assistant, Zigbee2MQTT (8333), Mosquitto (1883), Radarr (7878), Portainer, Netdata (19999)

### Storage Layout

Mergerfs pools multiple physical disks into a single `/srv/storage/media` mountpoint (configured by `ubuntu-bootstrap/02-storage.sh`):
```
/srv/storage/
├── downloads/    # qBittorrent downloads (dedicated disk)
├── disks/
│   ├── das1/     # Physical disk 1
│   └── das2/     # Physical disk 2
└── media/        # mergerfs pool of das1 + das2 (movies, tv, tv-uk)
```

### Custom Projects

**`projects/qbit-force-seed/`** — Python container that polls qBittorrent API and force-seeds recently completed torrents for a configurable number of days (default 15) to satisfy private tracker H&R rules.

## Configuration

Environment config is in `docker/.env` (secrets) with a template at `docker/env.example`. Key variables:
- `VPN_PROVIDER`, `VPN_TYPE`, `VPN_COUNTRIES` — VPN settings
- `LAN_SUBNETS` — Networks allowed to bypass VPN firewall
- `*_DIR` variables — Host paths for media storage
- `OPENVPN_USER`/`OPENVPN_PASSWORD` or `WIREGUARD_PRIVATE_KEY` — VPN credentials
- `PLEX_CLAIM` — Plex server claim token
- `QBITTORRENT_USER`/`QBITTORRENT_PASS` — qBittorrent credentials

All services run as `PUID:PGID` (1000:1000) for consistent file ownership.

See `docker/docs/01-stack.md` for detailed architecture documentation.
