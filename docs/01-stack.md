Home media + home automation stack (fresh plan)
================================================

Goal: rebuild the stack in this folder with a clean Compose setup, VPN-first egress, and sane defaults so LAN access keeps working even if the VPN drops.

What we found (old stack in `~/docker/arr-stack`)
-------------------------------------------------
- Uses `qmcgaw/gluetun` (OpenVPN to NordVPN) with `network_mode: service:gluetun` for qbittorrent/arr/plex/jellyfin/etc.
- Ports are all punched through gluetun, no healthchecks, and secrets live directly in `.env`.
- Everything shares the VPN namespace, which risks LAN access breaking when the VPN is down and forces Plex/Home Assistant traffic through the tunnel.

Proposed architecture
---------------------
- **Network layout**
  - Dedicated VPN gateway container (gluetun) with its firewall/kill-switch; privacy-sensitive apps share its network namespace (`network_mode: "service:gluetun"`).
  - Separate LAN-facing network for services that must stay reachable when the VPN drops (Plex/Jellyfin, Tautulli, Home Assistant). They can talk to VPN-only services over Docker networking, but egress is direct.
  - Healthchecks so VPN clients wait for gluetun healthy; VPN drop only impacts the VPN-routed group.
- **VPN gateway**
  - `qmcgaw/gluetun` is still the most maintained option and supports NordVPN OpenVPN/WireGuard, built-in firewall, port-forwarding, and `FIREWALL_OUTBOUND_SUBNETS`/`PRIVATE_SUBNETS` to allow LAN access while blocking WAN when the tunnel is down.
  - Configure `HEALTHCHECK` (e.g., `wget -qO- https://ipinfo.io/ip || exit 1`) and `depends_on: condition: service_healthy` for downstream containers.
- **Service grouping**
  - **VPN-routed (privacy required):** qbittorrent, prowlarr, sonarr, radarr, readarr, overseerr (if exposed externally), flaresolverr, bazarr (optional).
  - **LAN-first (should survive VPN outages):** Plex (as agreed), Jellyfin, Tautulli, Home Assistant (host or macvlan for mDNS/SSDP discovery), optional media dashboards.
- **Storage layout**
  - `./config/<service>/` for app configs, `./data/<service>/` if needed, and bind mounts to existing media/download paths.
  - `.env` for non-secret defaults; `.env.secrets` (git-ignored) for VPN creds, Plex claim, API keys.
- **Access & ingress**
  - Expose only the minimum host ports from gluetun for VPN-routed apps; expose LAN ports directly from LAN-facing containers.
  - Add optional reverse proxy (Traefik/Caddy) later for HTTPS on the LAN; not required to start.

Compose layout (planned)
------------------------
- `docker-compose.yml`: networks + gluetun VPN gateway with exposed ports for VPN-routed apps.
- `docker-compose.media.yml`: VPN-routed media automation stack.
- `docker-compose.lan.yml`: LAN-facing services (Plex/Jellyfin, Tautulli, Home Assistant).
- `env.example`: template for paths/IDs/timezone; `env.secrets.example`: keys for `.env.secrets` (untracked).

Current files created
---------------------
- `.gitignore` ignores `.env`, `.env.secrets`, `config/`, `data/`.
- `env.example` and `env.secrets.example` as templates.
- `docker-compose.yml` with networks and gluetun (ports exposed for VPN-routed services, healthcheck, firewall/kill-switch).
- `docker-compose.media.yml` for qbittorrent + arr stack + flaresolverr behind gluetun.
- `docker-compose.lan.yml` for Plex (non-VPN), Jellyfin, Tautulli, Home Assistant (host mode for discovery).

How to bring it up (once env files are filled)
----------------------------------------------
- Copy `env.example` to `.env`, and `env.secrets.example` to `.env.secrets`, then fill in paths/IDs and VPN/Plex secrets.
- Start everything: `docker compose -f docker-compose.yml -f docker-compose.media.yml -f docker-compose.lan.yml up -d`.
- Validate: `docker compose ... ps` to check health, and verify gluetun is `healthy` before VPN-routed services start.

Next steps
----------
- Confirm LAN subnet(s) for `LAN_SUBNETS` (for gluetun bypass) and any port-forwarding needs.
- Decide whether to use WireGuard or OpenVPN with Nord in gluetun; fill secrets accordingly.
- Wire in any extra services (e.g., bazarr, recyclarr) and a reverse proxy if desired.
- Migrate configs from `~/docker/arr-stack` selectively once the new stack is up and reachable.
