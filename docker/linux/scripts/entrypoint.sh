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
exec "$@"
