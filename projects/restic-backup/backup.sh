#!/usr/bin/env bash
set -euo pipefail

REPO="/srv/storage/media/backups/server"
SOURCE="/srv/excessum-server"
EXCLUDE_FILE="/etc/restic/excludes.txt"

log() { echo "$(date '+%Y-%m-%d %H:%M:%S') [INFO] $*"; }

log "Starting restic backup: $SOURCE -> $REPO"

restic -r "$REPO" --insecure-no-password backup \
  --exclude-file="$EXCLUDE_FILE" \
  --verbose \
  "$SOURCE"

log "Backup complete. Running forget/prune with retention policy..."

restic -r "$REPO" --insecure-no-password forget \
  --keep-daily 7 \
  --keep-weekly 4 \
  --keep-monthly 6 \
  --prune

log "Done."
