#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPOSE_DIR="$ROOT_DIR/docker"

cd "$COMPOSE_DIR"

export DOCKER_DEFAULT_PLATFORM=linux/amd64
export COMPOSE_PARALLEL_LIMIT=1

docker compose \
  -f docker-compose.yml \
  -f docker-compose.media.yml \
  -f docker-compose.lan.yml \
  up -d
