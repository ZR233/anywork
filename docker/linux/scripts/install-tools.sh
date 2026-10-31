#!/usr/bin/env bash
set -euo pipefail
source /opt/anywork-image/scripts/install-common.sh
temporary=$(mktemp -d)
trap 'rm -rf -- "$temporary"' EXIT
download "https://ziglang.org/download/${ZIG_VERSION}/zig-x86_64-linux-${ZIG_VERSION}.tar.xz" \
    "$ZIG_SHA256" "$temporary/zig.tar.xz"
mkdir -p /opt/zig
tar -xJf "$temporary/zig.tar.xz" -C /opt/zig --strip-components=1
download \
    "https://github.com/cargo-bins/cargo-binstall/releases/download/v${CARGO_BINSTALL_VERSION}/cargo-binstall-x86_64-unknown-linux-musl.tgz" \
    "$CARGO_BINSTALL_SHA256" "$temporary/binstall.tgz"
download \
    "https://github.com/rust-cross/cargo-zigbuild/releases/download/v${CARGO_ZIGBUILD_VERSION}/cargo-zigbuild-x86_64-unknown-linux-musl.tar.xz" \
    "$CARGO_ZIGBUILD_SHA256" "$temporary/zigbuild.tar.xz"
mkdir -p "$temporary/binstall" "$temporary/zigbuild"
tar -xzf "$temporary/binstall.tgz" -C "$temporary/binstall"
tar -xJf "$temporary/zigbuild.tar.xz" -C "$temporary/zigbuild" --strip-components=1
install -m 755 "$temporary/binstall/cargo-binstall" /opt/cargo/bin/cargo-binstall
install -m 755 "$temporary/zigbuild/cargo-zigbuild" /opt/cargo/bin/cargo-zigbuild
zig version
cargo binstall -V
cargo-zigbuild --version
