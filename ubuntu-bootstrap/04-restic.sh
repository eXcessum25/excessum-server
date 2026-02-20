#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

require_root

REPO="/srv/storage/media/backups/server"
RESTIC_CONF_DIR="/etc/restic"
EXCLUDE_FILE="${RESTIC_CONF_DIR}/excludes.txt"
BACKUP_BIN="/usr/local/bin/restic-backup"
CRON_FILE="/etc/cron.d/restic-backup"
PROJECT_DIR="${SCRIPT_DIR}/../projects/restic-backup"

# ── 1. Install restic ──────────────────────────────────────────────────────────
if command_exists restic; then
  log "restic already installed: $(restic version)"
else
  log "Installing bzip2 (needed to extract restic binary)..."
  apt-get install -y bzip2

  log "Installing latest restic binary from GitHub releases..."
  RESTIC_VERSION=$(curl -fsSL https://api.github.com/repos/restic/restic/releases/latest \
    | jq -r '.tag_name')
  RESTIC_VER="${RESTIC_VERSION#v}"
  TMP_DIR=$(mktemp -d)
  BZ2="${TMP_DIR}/restic.bz2"

  wget -q -O "$BZ2" \
    "https://github.com/restic/restic/releases/download/${RESTIC_VERSION}/restic_${RESTIC_VER}_linux_amd64.bz2"

  bunzip2 "$BZ2"
  install -m 755 "${TMP_DIR}/restic" /usr/local/bin/restic
  rm -rf "$TMP_DIR"

  log "Installed restic $(restic version)"
fi

# ── 2. Create /etc/restic config directory ─────────────────────────────────────
ensure_dir "$RESTIC_CONF_DIR"
chmod 700 "$RESTIC_CONF_DIR"

# ── 3. Copy exclude patterns ───────────────────────────────────────────────────
log "Installing exclude patterns -> ${EXCLUDE_FILE}"
cp "${PROJECT_DIR}/excludes.txt" "$EXCLUDE_FILE"
chmod 644 "$EXCLUDE_FILE"

# ── 4. Install backup script ───────────────────────────────────────────────────
log "Installing backup script -> ${BACKUP_BIN}"
cp "${PROJECT_DIR}/backup.sh" "$BACKUP_BIN"
chmod 755 "$BACKUP_BIN"

# ── 5. Initialise restic repo (idempotent) ─────────────────────────────────────
ensure_dir "$REPO"

if restic -r "$REPO" --insecure-no-password snapshots &>/dev/null; then
  log "Restic repo already initialised at ${REPO}"
else
  log "Initialising restic repo at ${REPO}"
  restic -r "$REPO" init --insecure-no-password
fi

# ── 6. Install cron job ────────────────────────────────────────────────────────
log "Installing cron job -> ${CRON_FILE}"
cat > "$CRON_FILE" <<EOF
# Daily restic backup of /srv/excessum-server at 05:00
0 5 * * * root /usr/local/bin/restic-backup >> /var/log/restic-backup.log 2>&1
EOF
chmod 644 "$CRON_FILE"

log "Done. Run a test backup with: sudo restic-backup"
log "Cron job scheduled daily at 05:00. Logs -> /var/log/restic-backup.log"
