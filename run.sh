#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPOSE_DIR="$ROOT_DIR/docker"

cd "$COMPOSE_DIR"

export DOCKER_DEFAULT_PLATFORM=linux/amd64

docker compose \
  -f docker-compose.vpn.yml \
  -f docker-compose.ha.yml \
  -f docker-compose.plex.yml \
  -f docker-compose.downloads.yml \
  -f docker-compose.admin.yml \
  up -d
