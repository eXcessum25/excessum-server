#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPOSE_DIR="$ROOT_DIR/docker"

cd "$COMPOSE_DIR"

export DOCKER_DEFAULT_PLATFORM=linux/amd64

COMPOSE=(
  docker compose
  --env-file .env
  --env-file .env.secrets
  -f docker-compose.vpn.yml
  -f docker-compose.ha.yml
  -f docker-compose.downloads.yml
  -f docker-compose.mediaserver.yml
  -f docker-compose.admin.yml
  -f docker-compose.immich.yml
  -f docker-compose.frigate.yml
  -f docker-compose.caddy.yml
)

# Refresh any image whose tag can move (e.g. :latest) before (re)creating containers.
# Pinned tags (e.g. TULIPROX_VERSION) just re-resolve to the same digest, so this is a no-op for them.
"${COMPOSE[@]}" pull

"${COMPOSE[@]}" up -d --remove-orphans
