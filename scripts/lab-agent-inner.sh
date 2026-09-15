#!/usr/bin/env bash
# Runs *inside* the lab TUI. uwsm-app starts a new terminal from the
# compositor, which does not have incus-admin (Hyprland launched before the
# group existed, and scopes drop it). Re-acquire the group, then exec the
# user agent wrapper (which applies desktop-lock on --prompt).

set -euo pipefail
# shellcheck source=ensure-incus-admin.sh
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/ensure-incus-admin.sh"

export OMARCHY_LAB_AGENT=1
export OMARCHY_DESKTOP_LOCK_REQUIRED=1

wrapper=${OMARCHY_AGENT_WRAPPER:-$HOME/.local/bin/omarchy-agent}
if [[ ! -x $wrapper ]]; then
  wrapper=$(command -v omarchy-agent)
fi

exec "$wrapper" "$@"
