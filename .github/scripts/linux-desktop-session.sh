#!/usr/bin/env bash
set -euo pipefail

if (( $# < 2 )); then
    printf 'Usage: %s ISOLATION_DIRECTORY COMMAND [ARG...]\n' "$0" >&2
    exit 2
fi

session_directory=$1
shift
umask 077
# Refuse reuse: the caller owns this new directory, never an existing keyring.
mkdir -m 700 -- "$session_directory"
session_directory=$(cd -- "$session_directory" && pwd -P)
trap 'rm -rf -- "$session_directory"' EXIT
mkdir -m 700 -- "$session_directory/config" "$session_directory/data" "$session_directory/runtime"
printf '\n' > "$session_directory/runtime/fixture-password"

env -u GNOME_KEYRING_CONTROL \
    XDG_CONFIG_HOME="$session_directory/config" \
    XDG_DATA_HOME="$session_directory/data" \
    XDG_RUNTIME_DIR="$session_directory/runtime" \
    dbus-run-session -- bash -euo pipefail -c '
        # A relative control directory keeps the Unix socket path short even
        # when the checkout is deep. The daemon alone changes its working dir.
        (
            cd -- "$XDG_RUNTIME_DIR"
            exec gnome-keyring-daemon --foreground --unlock --components=secrets \
                --control-directory=. < "$XDG_RUNTIME_DIR/fixture-password"
        ) &
        keyring_pid=$!
        trap '\''kill "$keyring_pid" 2>/dev/null || true; wait "$keyring_pid" 2>/dev/null || true'\'' EXIT
        gdbus wait --session --timeout 10 org.freedesktop.secrets
        # Keep this shell so its EXIT trap joins the daemon on command failure.
        "$@"
    ' -- "$@"
