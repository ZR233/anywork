#!/usr/bin/env bash
set -euo pipefail
if (( $# < 2 )); then
    printf 'Usage: %s IMAGE COMMAND [ARG...]\n' "$0" >&2
    exit 2
fi
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../.." && pwd -P)
image=$1
shift
arguments=(run --rm --init --pull=never --user "$(id -u):$(id -g)"
    --mount "type=bind,src=$root,dst=$root" --workdir "$root")
# CI keeps this dedicated cache outside the checkout so rust-cache recognizes
# registry/git packages as dependencies. Preserve the same paths in both hosts.
if [[ -n ${CARGO_HOME:-} ]]; then
    mkdir -p -- "$CARGO_HOME"
    cargo_cache=$(realpath -e -- "$CARGO_HOME")
    arguments+=(--mount "type=bind,src=$cargo_cache,dst=$cargo_cache"
        --env "CARGO_HOME=$cargo_cache")
fi
# Only explicit non-secret build controls cross the host/container boundary.
for variable in CARGO_INCREMENTAL CARGO_BUILD_JOBS CARGO_PROFILE_DEV_DEBUG CARGO_PROFILE_TEST_DEBUG; do
    if [[ -v $variable ]]; then
        arguments+=(--env "$variable=${!variable}")
    fi
done
if [[ -n ${PURE_REMOTE_HELPER_PREBUILT_DIR:-} ]]; then
    helper=$(realpath -e -- "$PURE_REMOTE_HELPER_PREBUILT_DIR")
    if [[ $helper != "$root/"* || ! -d $helper ]]; then
        printf 'PURE_REMOTE_HELPER_PREBUILT_DIR must be a directory inside %s\n' "$root" >&2
        exit 2
    fi
    arguments+=(--env "PURE_REMOTE_HELPER_PREBUILT_DIR=$helper")
fi
exec docker "${arguments[@]}" "$image" "$@"
