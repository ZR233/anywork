#!/usr/bin/env bash
set -euo pipefail
source /opt/anywork-image/scripts/install-common.sh
source /opt/anywork-image/codegen.env
temporary=$(mktemp -d)
trap 'rm -rf -- "$temporary"' EXIT
download \
    "https://github.com/fzyzcjy/flutter_rust_bridge/releases/download/v${FRB_CODEGEN_VERSION}/flutter_rust_bridge_codegen-x86_64-unknown-linux-musl-v${FRB_CODEGEN_VERSION}.tgz" \
    "$FRB_CODEGEN_SHA256" "$temporary/frb.tgz"
download \
    "https://github.com/cargo-bins/cargo-quickinstall/releases/download/cargo-expand-${CARGO_EXPAND_VERSION}/cargo-expand-${CARGO_EXPAND_VERSION}-x86_64-unknown-linux-musl.tar.gz" \
    "$CARGO_EXPAND_SHA256" "$temporary/expand.tar.gz"
tar -xzf "$temporary/frb.tgz" -C "$temporary" flutter_rust_bridge_codegen
tar -xzf "$temporary/expand.tar.gz" -C "$temporary" cargo-expand
install -m 755 "$temporary/flutter_rust_bridge_codegen" /opt/cargo/bin/flutter_rust_bridge_codegen
install -m 755 "$temporary/cargo-expand" /opt/cargo/bin/cargo-expand
flutter_rust_bridge_codegen --version
cargo-expand --version
