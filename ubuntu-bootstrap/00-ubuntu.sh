#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

require_root

log "Setting timezone to ${TZ}"
timedatectl set-timezone "${TZ}" || true

log "Updating apt + installing baseline packages"
apt-get update
apt-get install -y \
  ca-certificates curl wget git jq vim nano unzip \
  software-properties-common gnupg lsb-release \
  net-tools htop

log "Enabling unattended upgrades"
apt-get install -y unattended-upgrades
dpkg-reconfigure -f noninteractive unattended-upgrades || true

log "Installing mergerfs + fuse"
apt-get install -y fuse mergerfs

log "Done: base Ubuntu packages installed"
