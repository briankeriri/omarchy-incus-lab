#!/usr/bin/env bash
set -euo pipefail
plugin_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
omarchy plugin validate "$plugin_dir"
for script in desktop-lock.sh lab-agent.sh lab-agent-inner.sh ensure-incus-admin.sh status.sh; do
  [[ -x $plugin_dir/scripts/$script ]] || {
    echo "not executable: $script" >&2
    exit 1
  }
done
"$plugin_dir/scripts/desktop-lock.sh" --self-test
