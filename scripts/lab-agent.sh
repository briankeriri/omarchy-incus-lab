#!/usr/bin/env bash
# Restore the golden Incus VM snapshot, then open the host default agent.
# Fail closed: do not install Incus, create instances, or touch live Hyprland.

set -euo pipefail
# shellcheck source=ensure-incus-admin.sh
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/ensure-incus-admin.sh"

instance=${1:-${OMARCHY_LAB_INSTANCE:-omarchy-lab}}
snapshot=${2:-${OMARCHY_LAB_SNAPSHOT:-golden}}
agent_wrapper=${OMARCHY_AGENT_WRAPPER:-$HOME/.local/bin/omarchy-agent}
notify=${OMARCHY_NOTIFICATION_SEND:-omarchy-notification-send}
stop_timeout=${OMARCHY_LAB_STOP_TIMEOUT:-60}
agent_timeout=${OMARCHY_LAB_AGENT_TIMEOUT:-120}

say() {
  if command -v "$notify" >/dev/null 2>&1; then
    "$notify" "Lab agent" "$1"
  else
    printf '%s\n' "$1" >&2
  fi
}

instance_status() {
  incus list "$instance" --format csv --columns s
}

if ! command -v incus >/dev/null 2>&1; then
  say "Incus is not installed. Lab does nothing until you install it."
  exit 1
fi

if ! incus info "$instance" >/dev/null 2>&1; then
  say "No instance $instance. Lab does not create one."
  exit 1
fi

if ! incus snapshot show "$instance" "$snapshot" >/dev/null 2>&1; then
  say "No snapshot $snapshot on $instance. Lab will not invent one."
  exit 1
fi

say "Restoring $instance to $snapshot"

status=$(instance_status)
if [[ $status == RUNNING || $status == FROZEN ]]; then
  if ! incus stop "$instance" --timeout "$stop_timeout"; then
    status=$(instance_status)
    if [[ $status == RUNNING || $status == FROZEN ]]; then
      incus stop --force "$instance"
    fi
  fi
fi

incus snapshot restore "$instance" "$snapshot"
incus start "$instance"

instance_type=$(incus list "$instance" --format csv --columns t)
if [[ $instance_type == VIRTUAL-MACHINE* ]]; then
  deadline=$((SECONDS + agent_timeout))
  until incus exec "$instance" -- true >/dev/null 2>&1; do
    if ((SECONDS >= deadline)); then
      say "Guest agent on $instance did not become ready."
      exit 1
    fi
    sleep 2
  done
fi

prompt=$(
  cat <<EOF
Lab instance ${instance} is running from snapshot ${snapshot}.

Diagnose on the host. Reproduce and try fixes with: incus exec ${instance} -- …
Live ~/.config/hypr, ~/.config/omarchy, and /usr/share/omarchy are kernel
read-only in this window (bubblewrap). Switching to Agent mode does not
unlock them. Apply host edits only from Super+Shift+Ctrl+A after a yes.
EOF
)

if [[ ${OMARCHY_LAB_SKIP_AGENT:-} == 1 ]]; then
  say "Guest agent ready"
  exit 0
fi

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
inner=$script_dir/lab-agent-inner.sh
if [[ ! -x $inner ]]; then
  say "lab-agent-inner.sh is missing. Lab will not start an unlocked agent."
  exit 1
fi
export OMARCHY_AGENT_WRAPPER="$agent_wrapper"
export OMARCHY_LAB_AGENT=1

exec /usr/bin/omarchy-launch-tui --app-id=org.omarchy.agent-lab \
  "$inner" --inline --prompt "$prompt"
