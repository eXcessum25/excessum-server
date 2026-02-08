#!/usr/bin/env bash
set -euo pipefail

ufw_has_rule() {
  local rule="$1"
  ufw status | grep -Fq -- "$rule"
}

ufw_allow_lan_port() {
  local cidr="$1"
  local port="$2"
  local proto="${3:-tcp}"
  # string match is crude but works well enough for idempotency
  if ufw status | grep -Eq "${port}/${proto}.*ALLOW IN.*${cidr}"; then
    log "UFW already allows ${port}/${proto} from ${cidr}"
  else
    log "Allowing ${port}/${proto} from ${cidr}"
    ufw allow from "${cidr}" to any port "${port}" proto "${proto}"
  fi
}

ufw_delete_anywhere_port() {
  local port="$1"
  local proto="${2:-tcp}"

  # delete by numbered rules to avoid ambiguity
  while true; do
    local line
    line="$(ufw status numbered | grep -E "\] ${port}/${proto}.*ALLOW IN.*Anywhere" || true)"
    [[ -z "${line}" ]] && break
    local num
    num="$(sed -n 's/^\[\([0-9]\+\)\].*/\1/p' <<< "${line}")"
    log "Deleting global UFW rule: ${line}"
    ufw --force delete "${num}"
  done
}
