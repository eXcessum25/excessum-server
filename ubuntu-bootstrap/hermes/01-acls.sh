#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "${SCRIPT_DIR}/../lib/common.sh"

require_root

EXCESSUM_DIR="${EXCESSUM_DIR:-/srv/excessum-server}"

# ---- The model (agreed with Alan) ----
# hermes gets broad read/write across the repo -- it needs that to actually fix things --
# with named secrets/DBs denied individually. This is an accepted-risk model, not a perfect
# one: a NAMED user ACL entry overrides plain Unix permission bits, so the broad grant below
# silently re-exposes anything underneath it unless explicitly carved back out. Three rounds
# of Hermes's own self-audit (see /tmp/analysis.md from the session that built this) found a
# fresh batch of exposed secrets each time -- the list below is the result, not a guess.
# A fresh install only has the files that exist at setup time; services will create MORE
# secrets/DBs later (new containers, new config) that this script doesn't know about yet.
# Re-run this script periodically (or after adding a new service) and re-check for anything
# newly exposed -- Alan explicitly chose "patch per finding, keep the broad grant" over
# switching docker/config to an allowlist model, so that re-check is an ongoing cost of this
# approach, not a one-off.

IMMICH_DB="${EXCESSUM_DIR}/docker/config/immich-db"

# immich-db is Immich's live Postgres data directory (binary WAL/table files), bind-mounted
# straight into the running immich-postgres container. It is excluded from the sweep below
# entirely (never granted, not granted-then-stripped) -- there is no legitimate
# config-management reason to touch raw Postgres files directly, and even a momentary ACL
# change there is a needless risk given the alternative (just never touch it) costs nothing.
log "Granting hermes broad rwX on $EXCESSUM_DIR, EXCEPT immich-db which is never touched (regular + default ACL, so new files inherit it)"
if [[ -e "$IMMICH_DB" ]]; then
  find "$EXCESSUM_DIR" -path "$IMMICH_DB" -prune -o -print0 2>/dev/null | xargs -0 -I{} setfacl -m u:hermes:rwX "{}" 2>/dev/null || true
  find "$EXCESSUM_DIR" -path "$IMMICH_DB" -prune -o -type d -print0 2>/dev/null | xargs -0 -I{} setfacl -d -m u:hermes:rwX "{}" 2>/dev/null || true
else
  setfacl -R -m u:hermes:rwX "$EXCESSUM_DIR"
  setfacl -R -d -m u:hermes:rwX "$EXCESSUM_DIR"
fi

# docker/config accumulates root/uid-owned subdirs over time (containers that don't respect
# PUID/PGID create files as their own internal user: healthchecks ran as uid 999, jellyseerr/
# unpackerr/homeassistant/gluetun as root). Those evade the ACL the same way immich-db would
# if we hadn't excluded it, except here there's no live-database risk, so normalise ownership
# too rather than relying on the ACL alone.
log "Normalising ownership of docker/config to alan (except immich-db)"
find "${EXCESSUM_DIR}/docker/config" -mindepth 1 -maxdepth 1 ! -name "$(basename "$IMMICH_DB")" -print0 \
  | xargs -0 -I{} chown -R alan:alan "{}"

log "Locking down .env.secrets (plain Unix perms, not ACL -- it was world-readable before this)"
if [[ -e "${EXCESSUM_DIR}/docker/.env.secrets" ]]; then
  chmod o-rwx "${EXCESSUM_DIR}/docker/.env.secrets"
fi

# Denied outright: hermes gets NO access at all, not even read.
DENY_FILES=(
  "docker/.env.secrets"
  "docker/config/homeassistant/secrets.yaml"
  "docker/config/frigate/.jwt_secret"
  "docker/config/portainer/portainer.key"
  "docker/config/portainer/portainer.db"
  "docker/config/homeassistant/.storage/auth"
  "excessum.tail890eaf.ts.net.key"
)
log "Denying hermes on known secret files (skips any that don't exist, e.g. decommissioned services)"
for f in "${DENY_FILES[@]}"; do
  path="${EXCESSUM_DIR}/${f}"
  if [[ -e "$path" ]]; then
    setfacl -m u:hermes:--- "$path"
    log "  denied: $f"
  fi
done

# Fully stripped (no ACL entry at all -- protected by not being owned by/accessible to hermes
# via plain Unix bits instead): repo-internal paths that run with alan's/root's rights later
# and never show up in a `git diff` for alan to catch. immich-db is listed here too as a
# defensive assertion -- it should already have zero hermes ACL entries from being excluded
# above, this just guarantees it even if that exclusion logic is ever changed carelessly.
STRIP_DIRS=(
  "docker/config/immich-db"
  ".git/hooks"
  ".claude"
)
log "Stripping hermes's ACL entirely (regular + default) from immich-db (defensive, see above) and non-reviewable repo paths"
for d in "${STRIP_DIRS[@]}"; do
  path="${EXCESSUM_DIR}/${d}"
  if [[ -e "$path" ]]; then
    setfacl -R -x u:hermes "$path"
    setfacl -R -d -x u:hermes "$path"
    log "  stripped: $d"
  fi
done

log "Done. Spot-check as hermes (sudo -iu hermes):"
echo "  cat ${EXCESSUM_DIR}/docker/.env.secrets                     # Permission denied"
echo "  cat ${EXCESSUM_DIR}/docker/config/homeassistant/.storage/auth  # Permission denied"
echo "  test -w ${EXCESSUM_DIR}/.git/hooks && echo Y || echo n      # n"
echo "  test -w ${EXCESSUM_DIR}/.claude/settings.local.json && echo Y || echo n  # n"
echo "  ls ${EXCESSUM_DIR}/docker/config/immich-db                  # Permission denied, never touched"
echo "  touch ${EXCESSUM_DIR}/docker/config/healthchecks/.t && rm ${EXCESSUM_DIR}/docker/config/healthchecks/.t  # works"
