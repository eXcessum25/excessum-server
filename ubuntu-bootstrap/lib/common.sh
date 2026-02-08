#!/usr/bin/env bash
set -euo pipefail

# ---- User-editable defaults (override via .env if you want) ----
LAN_CIDR="${LAN_CIDR:-192.168.1.0/24}"
TZ="${TZ:-Europe/London}"

# If you store configs under /opt or similar
CONFIG_ROOT="${CONFIG_ROOT:-/opt/home}"

PRIMARY_USER="${PRIMARY_USER:-alan}"

PRIMARY_GROUP="${PRIMARY_GROUP:-alan}"

log()  { echo -e "\n\033[1;34m[INFO]\033[0m  $*"; }
warn() { echo -e "\n\033[1;33m[WARN]\033[0m  $*"; }
die()  { echo -e "\n\033[1;31m[ERR ]\033[0m  $*" >&2; exit 1; }

require_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    die "Run as root (e.g. sudo $0)"
  fi
}

command_exists() { command -v "$1" >/dev/null 2>&1; }

ensure_dir() {
  local d="$1"
  if [[ ! -d "$d" ]]; then
    log "Creating directory: $d"
    mkdir -p "$d"
  fi
}

backup_file() {
  local f="$1"
  if [[ -f "$f" ]]; then
    local b="${f}.bak.$(date +%F_%H%M%S)"
    log "Backing up $f -> $b"
    cp "$f" "$b"
  fi
}

ensure_owner() {
  local path="$1"
  local owner="$2"

  if [[ ! -e "$path" ]]; then
    warn "Path does not exist, cannot chown: $path"
    return 0
  fi

  current="$(stat -c '%U:%G' "$path" 2>/dev/null || true)"
  if [[ "$current" == "$owner" ]]; then
    log "Ownership already correct on $path ($owner)"
  else
    log "Setting ownership of $path to $owner"
    chown -R "$owner" "$path"
  fi
}
