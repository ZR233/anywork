#!/usr/bin/env bash
set -euo pipefail
toolchain=/opt/anywork-toolchain/rust-toolchain.toml
if ! cmp -s -- "$PWD/rust-toolchain.toml" "$toolchain"; then
    printf 'Linux build image: %s/rust-toolchain.toml is missing or differs from the image; build/select the matching image.\n' "$PWD" >&2
    exit 1
fi
if [[ -n ${RUSTUP_TOOLCHAIN+x} ]]; then
    printf 'Linux build image: RUSTUP_TOOLCHAIN must not override the workspace toolchain.\n' >&2
    exit 1
fi
mkdir -p -- "$HOME"
# OpenSSH requires getpwuid(), even for a purely numeric --user mapping.
# cwrap supplies container-only records without modifying /etc or changing UID.
uid=$(id -u)
gid=$(id -g)
if ! getent passwd "$uid" >/dev/null; then
    identity=$(mktemp -d "$HOME/.anywork-identity.XXXXXXXX")
    cp /etc/passwd "$identity/passwd"
    cp /etc/group "$identity/group"
    printf 'anywork-%s:x:%s:%s:container user:%s:/bin/bash\n' \
        "$uid" "$uid" "$gid" "$HOME" >> "$identity/passwd"
    if ! getent group "$gid" >/dev/null; then
        printf 'anywork-%s:x:%s:\n' "$gid" "$gid" >> "$identity/group"
    fi
    export NSS_WRAPPER_PASSWD="$identity/passwd" NSS_WRAPPER_GROUP="$identity/group"
    export LD_PRELOAD=/opt/anywork-image/libnss_wrapper.so
    getent passwd "$uid" >/dev/null
fi
exec "$@"
