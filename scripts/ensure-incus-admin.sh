# Re-exec this script with incus-admin if the login token is stale.
# Arch has setuid /usr/bin/newgrp but no `sg` symlink. argv0 `sg` is the
# non-interactive form. Source this; do not execute. No pkexec.

if id -nG | grep -qw incus-admin; then
  return 0
fi

if [[ ! -u /usr/bin/newgrp ]]; then
  return 0
fi

# printf reuses FORMAT for every argument, so 'exec %q ' would insert a
# literal exec before each arg and status.sh would see instance=exec.
cmd=$(printf '%q ' exec "$0" "$@")
exec -a sg /usr/bin/newgrp incus-admin -c "$cmd"
