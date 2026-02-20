#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

require_root

log "Installing Docker (idempotent)"

log "Removing old/conflicting Docker packages if present"
apt-get remove -y docker docker-engine docker.io containerd runc || true

log "Ensuring prerequisites"
apt-get update
apt-get install -y ca-certificates curl gnupg

log "Ensuring /etc/apt/keyrings exists"
install -m 0755 -d /etc/apt/keyrings

DOCKER_KEYRING="/etc/apt/keyrings/docker.gpg"
DOCKER_LIST="/etc/apt/sources.list.d/docker.list"
arch="$(dpkg --print-architecture)"
codename="$(. /etc/os-release && echo "$VERSION_CODENAME")"

log "Installing/updating Docker GPG key (no prompts)"
tmpkey="$(mktemp)"
curl -fsSL "https://download.docker.com/linux/ubuntu/gpg" | gpg --dearmor -o "${tmpkey}"
install -m 0644 "${tmpkey}" "${DOCKER_KEYRING}"
rm -f "${tmpkey}"

log "Writing Docker apt repo list"
cat > "${DOCKER_LIST}" <<EOF
deb [arch=${arch} signed-by=${DOCKER_KEYRING}] https://download.docker.com/linux/ubuntu ${codename} stable
EOF

log "Installing Docker Engine + Compose plugin"
apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

log "Enabling and starting Docker service"
systemctl enable --now docker

log "Adding ${PRIMARY_USER} to docker group (if user exists)"
if id -u "${PRIMARY_USER}" >/dev/null 2>&1; then
  if id -nG "${PRIMARY_USER}" | grep -qw docker; then
    log "User ${PRIMARY_USER} already in docker group"
  else
    usermod -aG docker "${PRIMARY_USER}"
    warn "User ${PRIMARY_USER} added to docker group. Log out/in (or reboot) for it to take effect."
  fi
else
  warn "User ${PRIMARY_USER} does not exist yet; skipping docker group assignment"
fi

log "Docker install complete"
log "Docker version:"
docker version || warn "docker version failed (service permissions/network?)"

log "Optional smoke test (non-fatal): hello-world"
docker run --rm hello-world || warn "hello-world failed (often due to no internet/DNS); Docker may still be fine"
