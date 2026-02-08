#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"
# shellcheck source=lib/ufw.sh
source "${SCRIPT_DIR}/lib/ufw.sh"

require_root

log "Configuring UFW defaults"
ufw default deny incoming
ufw default allow outgoing

# IMPORTANT: ensure SSH isn't blocked when enabling ufw
log "Ensuring SSH is allowed from LAN before tightening rules"
ufw_allow_lan_port "${LAN_CIDR}" 22 tcp

log "Allow Home Assistant UI (8123) from LAN only"
ufw_allow_lan_port "${LAN_CIDR}" 8123 tcp
ufw_delete_anywhere_port 8123 tcp

log "Allow Zigbee2MQTT UI (8333) from LAN only"
ufw_allow_lan_port "${LAN_CIDR}" 8333 tcp
ufw_delete_anywhere_port 8333 tcp

log "Leave Plex (32400) open to Anywhere (for now)"
if ufw status | grep -Eq "32400/tcp.*ALLOW IN"; then
  log "Plex rule already present"
else
  ufw allow 32400/tcp
fi

log "Allow Overseerr (5055) from LAN only"
ufw_allow_lan_port "${LAN_CIDR}" 5055 tcp
ufw_delete_anywhere_port 5055 tcp

log "Allow Portainer (9000) from LAN only"
ufw_allow_lan_port "${LAN_CIDR}" 9000 tcp
ufw_delete_anywhere_port 9000 tcp

log "Allow Netdata (19999) from LAN only"
ufw_allow_lan_port "${LAN_CIDR}" 19999 tcp
ufw_delete_anywhere_port 19999 tcp

log "Allow Dozzle (9999) from LAN only"
ufw_allow_lan_port "${LAN_CIDR}" 9999 tcp
ufw_delete_anywhere_port 9999 tcp

log "Now remove global SSH (Anywhere) rule for 22/tcp"
ufw_delete_anywhere_port 22 tcp


log "Disabling IPv6 in UFW (if enabled)"

UFW_DEFAULTS="/etc/default/ufw"

if grep -Eq '^IPV6=yes' "${UFW_DEFAULTS}"; then
  log "IPv6 is enabled in UFW – disabling it"
  sed -i 's/^IPV6=yes/IPV6=no/' "${UFW_DEFAULTS}"
  IPV6_CHANGED=true
else
  log "IPv6 already disabled in UFW"
  IPV6_CHANGED=false
fi

if [[ "${IPV6_CHANGED}" == "true" ]]; then
  log "Reloading UFW to apply IPv6 change"
  ufw reload
fi


log "Enable UFW (if not already enabled)"
ufw --force enable

log "UFW status:"
ufw status verbose
