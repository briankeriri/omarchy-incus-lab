#!/usr/bin/env bash
# Download packages on the host (has internet), push into the isolated VM.
# Does not attach NAT, does not change UFW, does not create instances.

set -euo pipefail
# shellcheck source=ensure-incus-admin.sh
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/ensure-incus-admin.sh"

instance=${1:-${OMARCHY_LAB_INSTANCE:-omarchy-lab}}
shift || true
notify=${OMARCHY_NOTIFICATION_SEND:-omarchy-notification-send}
agent_timeout=${OMARCHY_LAB_AGENT_TIMEOUT:-180}

say() {
  if command -v "$notify" >/dev/null 2>&1; then
    "$notify" "Lab packages" "$1" || true
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

pkgs=("$@")
if ((${#pkgs[@]} == 0)); then
  printf 'Packages to add (space-separated). Guest stays offline.\n> '
  read -r line
  # shellcheck disable=SC2206
  pkgs=($line)
fi

if ((${#pkgs[@]} == 0)); then
  say "No packages named."
  exit 1
fi

for p in "${pkgs[@]}"; do
  if [[ ! $p =~ ^[A-Za-z0-9][A-Za-z0-9@._+-]*$ ]]; then
    say "Rejected package name: $p"
    exit 1
  fi
done

status=$(incus list "$instance" --format csv --columns s)
if [[ $status != RUNNING ]]; then
  incus start "$instance"
fi

deadline=$((SECONDS + agent_timeout))
until incus exec "$instance" -- true >/dev/null 2>&1; do
  if ((SECONDS >= deadline)); then
    say "Guest agent on $instance did not become ready."
    exit 1
  fi
  sleep 2
done

cache=$(mktemp -d)
trap 'rm -rf "$cache"' EXIT

say "Downloading on this PC: ${pkgs[*]}"
sudo pacman -Syw --noconfirm --cachedir "$cache" "${pkgs[@]}"

incus exec "$instance" -- mkdir -p /tmp/lab-pkgs
shopt -s nullglob
files=("$cache"/*.pkg.tar.*)
if ((${#files[@]} == 0)); then
  say "Nothing landed in the download cache."
  exit 1
fi

for f in "${files[@]}"; do
  [[ $f == *.sig ]] && continue
  incus file push "$f" "$instance/tmp/lab-pkgs/$(basename "$f")"
done

say "Installing in $instance (still isolated)"
incus exec "$instance" -- bash -lc 'shopt -s nullglob; set -- /tmp/lab-pkgs/*.pkg.tar.*; [[ $# -gt 0 ]] || exit 1; pacman -U --noconfirm "$@"'

say "Installed ${pkgs[*]}. Save golden from the panel only while still isolated."
printf '\nPress Enter to close.\n'
read -r _
