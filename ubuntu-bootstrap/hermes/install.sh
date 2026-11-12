#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

"${SCRIPT_DIR}/00-user.sh"
"${SCRIPT_DIR}/01-acls.sh"
"${SCRIPT_DIR}/02-docker-proxy.sh"
"${SCRIPT_DIR}/03-sudoers.sh"

echo
echo "Hermes access layer installed. See README.md in this directory for what's NOT covered"
echo "(installing the hermes-agent tool itself and its gateway service) and known gaps."
