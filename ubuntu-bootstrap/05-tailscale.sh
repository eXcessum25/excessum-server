#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

require_root

if ! command_exists tailscale; then
    log "Installing Tailscale"
    curl -fsSL https://tailscale.com/install.sh | sh
else
    log "Tailscale already installed: $(tailscale version)"
fi

log "Enabling IP forwarding"
if ! grep -q "^net.ipv4.ip_forward=1" /etc/sysctl.conf; then
    echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
    sysctl -p
else
    log "IP forwarding already enabled"
fi

log "Enabling and starting tailscaled"
systemctl enable --now tailscaled

log "Fetching Tailscale HTTPS certificate (requires prior 'tailscale up' authentication)"
if tailscale status &>/dev/null; then
    tailscale cert
    log "Certificate fetched. Your Magic DNS hostname: $(tailscale status --json | python3 -c 'import sys,json; s=json.load(sys.stdin); print(s["Self"]["DNSName"].rstrip("."))')"
else
    warn "Tailscale not yet authenticated — skipping cert fetch"
    log "After running 'sudo tailscale up', re-run this script to fetch the certificate"
fi

log "Installing monthly cert renewal cron job"
CRON_JOB="0 0 1 * * root tailscale cert && docker restart caddy"
if ! grep -qF "tailscale cert" /etc/crontab; then
    echo "${CRON_JOB}" >> /etc/crontab
    log "Cron job added"
else
    log "Cert renewal cron already present"
fi

log ""
log "To authenticate: run 'sudo tailscale up'"
log "Then re-run this script to fetch the HTTPS certificate"
log "Admin console: https://login.tailscale.com/admin (enable Magic DNS + HTTPS Certificates)"
