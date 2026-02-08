#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

require_root

SSHD_CONFIG="/etc/ssh/sshd_config"

log "Hardening SSH configuration"

backup="${SSHD_CONFIG}.bak.$(date +%F_%H%M%S)"
log "Backing up sshd_config to ${backup}"
cp "${SSHD_CONFIG}" "${backup}"

set_sshd_option() {
  local key="$1"
  local value="$2"

  if grep -Eq "^[#[:space:]]*${key}[[:space:]]+" "${SSHD_CONFIG}"; then
    log "Updating ${key} ${value}"
    sed -i "s|^[#[:space:]]*${key}[[:space:]].*|${key} ${value}|" "${SSHD_CONFIG}"
  else
    log "Adding ${key} ${value}"
    echo "${key} ${value}" >> "${SSHD_CONFIG}"
  fi
}

# ---- Required settings ----
set_sshd_option "PermitRootLogin" "no"
set_sshd_option "PasswordAuthentication" "no"
set_sshd_option "PubkeyAuthentication" "yes"
set_sshd_option "ChallengeResponseAuthentication" "no"
set_sshd_option "UsePAM" "yes"

# ---- Optional hardening ----
set_sshd_option "MaxAuthTries" "3"
set_sshd_option "LoginGraceTime" "30"

log "Validating SSH configuration"
sshd -t

log "Restarting SSH service"
systemctl restart ssh

log "SSH hardening complete"
log "IMPORTANT: Ensure you have working SSH key access before closing this session"
