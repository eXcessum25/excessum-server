#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "${SCRIPT_DIR}/../lib/common.sh"

require_root

STATUS_WRAPPER="/usr/local/sbin/hermes-systemctl-status"
LOGS_WRAPPER="/usr/local/bin/hermes-docker-logs"
SUDOERS_FILE="/etc/sudoers.d/hermes"

log "Installing wrapper scripts"
install -m 0755 -o root -g root "${SCRIPT_DIR}/sbin/hermes-systemctl-status" "$STATUS_WRAPPER"
install -m 0755 -o root -g root "${SCRIPT_DIR}/bin/hermes-docker-logs" "$LOGS_WRAPPER"
echo "  $STATUS_WRAPPER (needs the sudoers rule below)"
echo "  $LOGS_WRAPPER (no sudoers needed -- talks to the docker proxy on localhost as an ordinary user)"

# Exact per-disk commands, no wildcard trailing arguments: "/dev/sd*" with a wildcard also
# matches extra arguments appended after it (e.g. "-a /dev/sda -s off"), letting hermes change
# disk settings, not just read them.
log "Finding block devices for the smartctl rule"
SMARTCTL_RULES=""
for dev in /dev/sd? /dev/nvme?n?; do
  [[ -b "$dev" ]] || continue
  SMARTCTL_RULES="${SMARTCTL_RULES}hermes ALL=(root) NOPASSWD: /usr/sbin/smartctl -a ${dev}
"
done
[[ -n "$SMARTCTL_RULES" ]] || die "no block devices found under /dev/sd? or /dev/nvme?n?"

log "Writing $SUDOERS_FILE"
cat > /tmp/sudoers.hermes <<EOF
# Read-only diagnostics for the hermes caretaker account. No write/change commands.
${SMARTCTL_RULES}hermes ALL=(root) NOPASSWD: /usr/sbin/ufw status
hermes ALL=(root) NOPASSWD: ${STATUS_WRAPPER} *
EOF
visudo -cf /tmp/sudoers.hermes || die "sudoers syntax check failed, aborting"
install -m 0440 -o root -g root /tmp/sudoers.hermes "$SUDOERS_FILE"
rm -f /tmp/sudoers.hermes

log "Done. Verify as hermes (sudo -iu hermes):"
echo "  sudo smartctl -a /dev/sda -s off              # Sorry, user hermes is not allowed ..."
echo "  sudo ufw status                                # works"
echo "  sudo ${STATUS_WRAPPER} docker                  # works"
echo "  sudo ${STATUS_WRAPPER} -H alan@localhost docker  # rejected argument: -H"
echo "  hermes-docker-logs dozzle 50                    # works, no sudo"
