#!/usr/bin/env bash
# Replace the golden snapshot only while the nic is isolated. Never snapshot NAT.

set -euo pipefail
# shellcheck source=ensure-incus-admin.sh
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/ensure-incus-admin.sh"

instance=${1:-${OMARCHY_LAB_INSTANCE:-omarchy-lab}}
snapshot=${2:-${OMARCHY_LAB_SNAPSHOT:-golden}}
notify=${OMARCHY_NOTIFICATION_SEND:-omarchy-notification-send}

say() {
  if command -v "$notify" >/dev/null 2>&1; then
    "$notify" "Lab snapshot" "$1" || true
  fi
  printf '%s\n' "$1"
}

if ! command -v incus >/dev/null 2>&1; then
  say "Incus is not installed."
  exit 1
fi

if ! incus info "$instance" >/dev/null 2>&1; then
  say "No instance $instance."
  exit 1
fi

network=$(incus config device get "$instance" eth0 network 2>/dev/null || true)
if [[ $network != labnet && $network != isolated ]]; then
  say "Nic is ${network:-unknown}. Isolate on labnet before saving golden."
  exit 1
fi

printf 'Replace snapshot %s on %s? Type yes: ' "$snapshot" "$instance"
read -r confirm
if [[ $confirm != yes ]]; then
  say "Cancelled."
  exit 0
fi

if incus snapshot show "$instance" "$snapshot" >/dev/null 2>&1; then
  incus snapshot delete "$instance" "$snapshot"
fi
incus snapshot create "$instance" "$snapshot"
say "Saved $snapshot (isolated, network=$network)."
printf '\nPress Enter to close.\n'
read -r _
