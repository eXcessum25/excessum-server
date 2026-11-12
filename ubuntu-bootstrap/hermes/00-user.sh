#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "${SCRIPT_DIR}/../lib/common.sh"

require_root

HERMES_UID=2000
HERMES_GID=2000
HERMES_HOME="/srv/hermes"

# Fixed uid/gid, not auto-picked: `useradd --system` auto-assigns the first free system uid,
# which on this box collided with uid 999 already used internally by bind-mounted container
# data (Immich's Postgres, healthchecks' db/web) -- a painful one to debug after the fact.
# Picking an explicit, unused-by-anything id up front avoids that whole class of problem.
if getent passwd hermes >/dev/null; then
  current_uid="$(id -u hermes)"
  if [[ "$current_uid" != "$HERMES_UID" ]]; then
    die "user hermes already exists with uid $current_uid, expected $HERMES_UID -- resolve manually (this script won't try to renumber a live uid)"
  fi
  log "hermes user already exists (uid $HERMES_UID), skipping creation"
else
  log "Creating group hermes (gid $HERMES_GID)"
  groupadd -g "$HERMES_GID" hermes
  log "Creating user hermes (uid $HERMES_UID), home $HERMES_HOME, locked password, no login shell access except via sudo -iu hermes"
  useradd -u "$HERMES_UID" -g "$HERMES_GID" -d "$HERMES_HOME" -m -s /bin/bash hermes
  passwd -l hermes
fi

log "Ensuring hermes is in adm + systemd-journal (read system/journal logs, no write anywhere)"
usermod -aG adm,systemd-journal hermes

log "hermes user ready: $(id hermes)"
echo "Reach it with: sudo -iu hermes"
