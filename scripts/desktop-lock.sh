#!/usr/bin/env bash
# Exec a command with Omarchy desktop trees read-only (bubblewrap bind-mounts).
# This is a kernel lock: it still holds if the agent leaves Ask mode.
# User wrapper only. Never edits /usr/share/omarchy.
#
# systemd-run --user --scope cannot set ReadOnlyPaths (not a service exec
# property). A transient user *service* can, but it drops incus-admin, so
# the Incus unix socket refuses the client. bwrap keeps the caller's creds
# when this script is already in incus-admin (lab-agent-inner newgrp).

set -euo pipefail

if ! command -v bwrap >/dev/null 2>&1; then
  echo "omarchy-desktop-lock: bubblewrap (bwrap) is required" >&2
  exit 1
fi

ro_paths=(
  /usr/share/omarchy
  "$HOME/.config/hypr"
  "$HOME/.config/omarchy"
  "$HOME/.config/alacritty"
  "$HOME/.config/foot"
  "$HOME/.config/kitty"
  "$HOME/.config/ghostty"
)

bwrap_args=(
  --die-with-parent
  --bind / /
  --dev-bind /dev /dev
  --proc /proc
)

for path in "${ro_paths[@]}"; do
  bwrap_args+=(--ro-bind-try "$path" "$path")
done

self_test() {
  local probe=$HOME/.config/hypr/.omarchy-desktop-lock-probe
  if touch "$probe" >/dev/null 2>&1; then
    rm -f "$probe"
    echo "omarchy-desktop-lock: ~/.config/hypr is writable; lock failed" >&2
    exit 1
  fi
  if [[ ! -r $HOME/.config/hypr/bindings.lua ]]; then
    echo "omarchy-desktop-lock: cannot read ~/.config/hypr (diagnose needs this)" >&2
    exit 1
  fi
  if id -nG | grep -qw incus-admin && command -v incus >/dev/null 2>&1; then
    incus list "${OMARCHY_LAB_INSTANCE:-omarchy-lab}" --format csv --columns n >/dev/null
  fi
  echo "omarchy-desktop-lock: ok"
  exit 0
}

export OMARCHY_DESKTOP_LOCK=1

if [[ ${1:-} == --self-test ]]; then
  exec bwrap "${bwrap_args[@]}" -- bash -c "$(declare -f self_test); self_test"
fi

if (($# == 0)); then
  echo "usage: omarchy-desktop-lock <command> [args...]" >&2
  exit 1
fi

exec bwrap "${bwrap_args[@]}" -- "$@"
