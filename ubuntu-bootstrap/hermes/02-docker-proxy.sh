#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "${SCRIPT_DIR}/../lib/common.sh"

require_root

PROXY="hermes-docker-proxy"
IMAGE="wollomatic/socket-proxy:1.13.2"
PORT=2375

# hermes talks to Docker through this proxy on 127.0.0.1, never the raw socket or the
# `docker` group (both root-equivalent). We tried tecnativa/docker-socket-proxy first: it can
# only gate whole API *sections*, so e.g. enabling containers also exposed every container's
# env vars via inspect (API keys, VPN creds, DB passwords) and archive/export (arbitrary file
# read inside any container, bypassing filesystem ACLs entirely) -- a capability gap in that
# image, not a config mistake. wollomatic allows exact method+path regexes instead, so we can
# permit precisely what's needed and nothing else.
#
# Allowed:
#   GET  version/_ping/containers-list/logs/stats, images list+inspect, volumes list+inspect
#   POST container restart/start/stop, image prune (dangling only -- see below)
#   DELETE container/image/volume, each with NO query string allowed
# The DELETE and prune restrictions lean on two things together: (1) no query string allowed
# by the proxy at all on those routes, which blocks `force=1` (the `-f` flag) and the `-a`
# filter docker image prune -a adds; and (2) the daemon itself already refuses to delete a
# running container or an in-use image/volume without force=1. Combined, that gives "stopped
# containers only, unreferenced images/volumes only" without the proxy needing to understand
# container/volume state itself.
# Still refused: inspect on /containers (the env-var leak route), exec/create/run/cp,
# archive/export, any query string on the DELETE/prune routes above, system prune, networks,
# swarm, and the raw socket.
log "Removing old proxy container $PROXY if present"
docker rm -f "$PROXY" >/dev/null 2>&1 || true

log "Pulling $IMAGE"
docker pull "$IMAGE"

DOCKER_GID="$(getent group docker | cut -d: -f3)"
[[ -n "$DOCKER_GID" ]] || die "couldn't resolve the docker group's gid"

log "Starting $PROXY (read-only container, no caps, non-root uid, --network host)"
# --network host (not -p 127.0.0.1:...:...): wollomatic checks the client's source IP
# (-allowfrom, default 127.0.0.1/32) -- a bridge-published port would show the docker
# bridge gateway as the source and get rejected.
docker run -d \
  --name "$PROXY" \
  --restart unless-stopped \
  --network host \
  --read-only \
  --cap-drop=ALL \
  --security-opt no-new-privileges \
  --user "65534:${DOCKER_GID}" \
  -v /var/run/docker.sock:/var/run/docker.sock:ro \
  "$IMAGE" \
  -proxyport="${PORT}" \
  -allowGET='/v1\..{1,2}/(version|_ping|containers/json|containers/[^/]+/logs|containers/[^/]+/stats|images/json|images/[^/]+/json|volumes|volumes/[^/]+)(\?.*)?' \
  -allowPOST='/v1\..{1,2}/containers/[^/]+/(restart|start|stop)(\?.*)?|/v1\..{1,2}/images/prune' \
  -allowDELETE='/v1\..{1,2}/(containers|images|volumes)/[^/]+'

log "Setting DOCKER_HOST for hermes's interactive shells (sudo -iu hermes)"
cat > /etc/profile.d/hermes-docker-host.sh <<'EOF'
# hermes talks to Docker through the filtered proxy, never the raw socket.
if [ "$(id -un 2>/dev/null)" = "hermes" ]; then
  export DOCKER_HOST=tcp://127.0.0.1:2375
fi
EOF
chmod 644 /etc/profile.d/hermes-docker-host.sh

echo
echo "NOTE: if/when the Hermes gateway systemd service is installed (hermes gateway install),"
echo "add Environment=DOCKER_HOST=tcp://127.0.0.1:${PORT} to its unit so the gateway process"
echo "(not just interactive shells) can reach the proxy too -- that install is a separate,"
echo "not-yet-automated step."

log "Done. Verify as hermes (sudo -iu hermes):"
echo "  docker images | head -3                       # works"
echo "  docker volume ls | head -3                     # works"
echo "  docker stats --no-stream                       # works"
echo "  docker inspect $PROXY                          # 403 (env-var leak route, unchanged)"
echo "  docker rm -f <a running container>             # refused"
echo "  docker image prune -a                          # refused"
echo "  docker exec / docker run / docker cp           # refused, unchanged"
