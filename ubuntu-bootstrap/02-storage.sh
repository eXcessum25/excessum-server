#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

require_root

FSTAB="/etc/fstab"
FUSECONF="/etc/fuse.conf"

# ---- fstab entries (exact lines you asked for) ----
LINE1='UUID=bfdee8ea-d307-4a07-9cac-43484bc2ef19  /srv/storage/downloads  ext4  defaults,noatime  0  2'
LINE2='UUID=b5e6ecba-b443-4896-b552-1f0c696e86c4  /srv/storage/disks/das1  ext4  defaults,noatime  0  2'
LINE3='UUID=e074759d-70b7-4c2c-8a73-7b24d7526e34  /srv/storage/disks/das2  ext4  defaults,noatime  0  2'
LINE4='/srv/storage/disks/*  /srv/storage/media  fuse.mergerfs  defaults,allow_other,use_ino,category.create=mfs,nonempty  0  0'

# Derived mountpoints (2nd column)
MP1='/srv/storage/downloads'
MP2='/srv/storage/disks/das1'
MP3='/srv/storage/disks/das2'
MP4='/srv/storage/media'

OWNER="${PRIMARY_USER}:${PRIMARY_GROUP}"

fstab_has_exact_line() {
  local line="$1"
  grep -Fqx -- "$line" "$FSTAB"
}

append_fstab_line_if_missing() {
  local line="$1"
  if fstab_has_exact_line "$line"; then
    log "fstab already contains: $line"
  else
    log "Appending to fstab: $line"
    echo "$line" >> "$FSTAB"
  fi
}

enable_user_allow_other_if_needed() {
  # mergerfs allow_other requires this
  if [[ ! -f "$FUSECONF" ]]; then
    warn "$FUSECONF not found. If mergerfs mount fails with allow_other, install fuse and add 'user_allow_other'."
    return 0
  fi

  if grep -Eq '^[[:space:]]*user_allow_other[[:space:]]*$' "$FUSECONF"; then
    log "fuse.conf already has user_allow_other"
    return 0
  fi

  log "Enabling user_allow_other in $FUSECONF (required for mergerfs allow_other)"
  # Uncomment if present, otherwise append
  if grep -Eq '^[[:space:]]*#?[[:space:]]*user_allow_other[[:space:]]*$' "$FUSECONF"; then
    sed -i 's/^[[:space:]]*#\?[[:space:]]*user_allow_other[[:space:]]*$/user_allow_other/' "$FUSECONF"
  else
    echo "user_allow_other" >> "$FUSECONF"
  fi
}

log "Ensuring storage directories exist"
ensure_dir "/srv/storage/downloads"
ensure_dir "/srv/storage/disks/das1"
ensure_dir "/srv/storage/disks/das2"
ensure_dir "/srv/storage/media"

backup_file "$FSTAB"

log "Ensuring required fstab entries exist"
append_fstab_line_if_missing "$LINE1"
append_fstab_line_if_missing "$LINE2"
append_fstab_line_if_missing "$LINE3"
append_fstab_line_if_missing "$LINE4"

enable_user_allow_other_if_needed

log "Mounting (targeted mounts first)"
mountpoint -q "$MP1" || (log "Mounting $MP1" && mount "$MP1" || true)
mountpoint -q "$MP2" || (log "Mounting $MP2" && mount "$MP2" || true)
mountpoint -q "$MP3" || (log "Mounting $MP3" && mount "$MP3" || true)
mountpoint -q "$MP4" || (log "Mounting $MP4" && mount "$MP4" || true)

log "Running mount -a (will error if other fstab entries are broken)"
mount -a

log "Setting correct ownership"

log "Ensuring ownership of storage mountpoints"
ensure_owner "$MP1" "$OWNER"
ensure_owner "$MP2" "$OWNER"
ensure_owner "$MP3" "$OWNER"
ensure_owner "$MP4" "$OWNER"

log "Mounted filesystems:"
findmnt "$MP1" || true
findmnt "$MP2" || true
findmnt "$MP3" || true
findmnt "$MP4" || true

log "Done."
