#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPOSE_DIR="$ROOT_DIR/docker"

cd "$COMPOSE_DIR"

docker compose \
  -f docker-compose.yml \
  -f docker-compose.media.yml \
  -f docker-compose.lan.yml \
  down
