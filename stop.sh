#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPOSE_DIR="$ROOT_DIR/docker"

cd "$COMPOSE_DIR"

docker compose \
  --env-file .env \
  --env-file .env.secrets \
  -f docker-compose.vpn.yml \
  -f docker-compose.plex.yml \
  -f docker-compose.ha.yml \
  -f docker-compose.downloads.yml \
  -f docker-compose.admin.yml \
  -f docker-compose.personal.yml \
  down
