#!/usr/bin/env bash
# Emit one JSON object describing the lab. Never creates instances.

set -euo pipefail
# shellcheck source=ensure-incus-admin.sh
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/ensure-incus-admin.sh"

instance=${1:-${OMARCHY_LAB_INSTANCE:-omarchy-lab}}
snapshot=${2:-${OMARCHY_LAB_SNAPSHOT:-golden}}

emit() {
  local state=$1
  local vm_type=${2:-}
  local isolated=${3:-false}
  local has_snapshot=${4:-false}
  local detail=${5:-}
  jq -n \
    --arg state "$state" \
    --arg instance "$instance" \
    --arg snapshot "$snapshot" \
    --arg type "$vm_type" \
    --argjson isolated "$isolated" \
    --argjson hasSnapshot "$has_snapshot" \
    --arg detail "$detail" \
    '{
      state: $state,
      instance: $instance,
      snapshot: $snapshot,
      type: $type,
      isolated: $isolated,
      hasSnapshot: $hasSnapshot,
      detail: $detail
    }'
}

if ! command -v incus >/dev/null 2>&1; then
  emit missing-incus
  exit 0
fi

err=$(incus info "$instance" 2>&1) || {
  if grep -qiE 'permission|not authorized|incus.socket|unix socket' <<<"$err"; then
    emit no-permission "" false false "incus socket not reachable"
    exit 0
  fi
  emit missing-instance
  exit 0
}

vm_type=$(awk -F': *' '/^Type:/{print $2; exit}' <<<"$err")
status=$(incus list "$instance" --format csv --columns s 2>/dev/null || echo UNKNOWN)

has_snapshot=false
if incus snapshot show "$instance" "$snapshot" >/dev/null 2>&1; then
  has_snapshot=true
fi

network=$(incus config device get "$instance" eth0 network 2>/dev/null || true)
isolated=false
[[ $network == labnet || $network == isolated ]] && isolated=true

state=stopped
[[ $status == RUNNING ]] && state=running

emit "$state" "$vm_type" "$isolated" "$has_snapshot" "$network"
