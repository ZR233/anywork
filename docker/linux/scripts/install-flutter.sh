#!/usr/bin/env bash
set -euo pipefail
source /opt/anywork-image/scripts/install-common.sh
temporary=$(mktemp -d)
trap 'rm -rf -- "$temporary"' EXIT
download \
    "https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_${FLUTTER_VERSION}-stable.tar.xz" \
    "$FLUTTER_SHA256" "$temporary/flutter.tar.xz"
tar -xJf "$temporary/flutter.tar.xz" -C /opt
# SDK initialization only; never run a project command inside the SDK.
cd /opt/anywork-toolchain
git config --system --add safe.directory /opt/flutter
/opt/flutter/bin/flutter config --no-analytics --enable-linux-desktop
/opt/flutter/bin/flutter precache --linux
/opt/flutter/bin/flutter --version
