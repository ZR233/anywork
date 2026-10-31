#!/usr/bin/env bash
set -euo pipefail
source /opt/anywork-image/scripts/install-common.sh
temporary=$(mktemp -d)
trap 'rm -rf -- "$temporary"' EXIT
download \
    "https://static.rust-lang.org/rustup/archive/${RUSTUP_VERSION}/x86_64-unknown-linux-gnu/rustup-init" \
    "$RUSTUP_SHA256" "$temporary/rustup-init"
chmod +x "$temporary/rustup-init"
"$temporary/rustup-init" -y --no-modify-path --default-toolchain none
# rustup reads channel/profile/components/targets directly from the original file.
cd /opt/anywork-toolchain
rustup show
rustc --version
cargo --version
