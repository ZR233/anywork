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
session_identity=$(stat -c '%d:%i:%u' -- "$session_directory")
cleanup() {
    local status=$?
    trap - EXIT
    if ! python3 - "$session_directory" "$session_identity" <<'PY'
import json
import os
from pathlib import Path
import shutil
import stat
import subprocess
import sys

root = Path(sys.argv[1])
identity = tuple(map(int, sys.argv[2].split(":")))
expected = {
    str(root / "runtime/doc"): "fuse.portal",
    str(root / "runtime/gvfs"): "fuse.gvfsd-fuse",
}

def check_root():
    value = root.lstat()
    if (not stat.S_ISDIR(value.st_mode)
            or (value.st_dev, value.st_ino, value.st_uid) != identity
            or value.st_uid != os.getuid()):
        raise RuntimeError("private desktop session directory identity changed")

def mounts():
    result = subprocess.run(
        ["findmnt", "--json", "--list", "--output", "ID,TARGET,FSTYPE,FS-OPTIONS"],
        check=True, stdout=subprocess.PIPE, text=True,
    )
    return [
        mount for mount in json.loads(result.stdout)["filesystems"]
        if mount["target"] == str(root) or mount["target"].startswith(f"{root}/")
    ]

check_root()
owned = mounts()
seen = set()
for mount in owned:
    target = mount["target"]
    if (target in seen or expected.get(target) != mount["fstype"]
            or f"user_id={os.getuid()}" not in mount["fs-options"].split(",")):
        raise RuntimeError(f"refusing unexpected private session mount: {target}")
    seen.add(target)

for mount in owned:
    check_root()
    current = [value for value in mounts() if value["target"] == mount["target"]]
    if not current:
        continue
    if current != [mount]:
        raise RuntimeError("private desktop session mount identity changed")
    subprocess.run(["fusermount3", "-u", "--", mount["target"]], check=True)

check_root()
if mounts():
    raise RuntimeError("private desktop session mounts remain; preserving directory")
shutil.rmtree(root)
PY
    then
        printf 'Private desktop session cleanup failed; preserving remaining directory: %s\n' "$session_directory" >&2
        if (( status == 0 )); then status=1; fi
    fi
    exit "$status"
}
trap cleanup EXIT
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
