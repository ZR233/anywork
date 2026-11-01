#!/bin/sh
# Xcode consumes xtask's prebuilt inputs; it never invokes Cargo or cross compilers.
set -eu
app="$TARGET_BUILD_DIR/$CONTENTS_FOLDER_PATH"
bridge="$app/Frameworks/libpl_studio_bridge.dylib"
helpers="$app/Resources/data/remote-helper"
licenses="$app/Resources/licenses"
mkdir -p "$licenses"
/usr/bin/ditto "$PROJECT_DIR/LICENSE.flutter" "$licenses/LICENSE.flutter"
/usr/bin/ditto "$PROJECT_DIR/../../../LICENSE" "$licenses/LICENSE.anywork"
/usr/bin/ditto "$PROJECT_DIR/../../pl-studio-runtime/THIRD_PARTY_NOTICES.md" "$licenses/THIRD_PARTY_NOTICES.md"
if [ "${ANYWORK_DEMO:-}" = "true" ]; then
  rm -f "$bridge"
  rm -rf "$helpers"
  exit 0
fi
: "${ANYWORK_BRIDGE_LIBRARY:?Run cargo xtask build-gui or run-gui to build the Rust bridge}"
: "${ANYWORK_REMOTE_HELPER_DIR:?xtask must prepare bundled remote helpers}"
test -f "$ANYWORK_BRIDGE_LIBRARY"
for target in aarch64-unknown-linux-musl x86_64-unknown-linux-musl; do
  test -f "$ANYWORK_REMOTE_HELPER_DIR/$target/pl-remote-helper.zst"
  test -f "$ANYWORK_REMOTE_HELPER_DIR/$target/pl-remote-helper.metadata.json"
done
mkdir -p "$app/Frameworks" "$helpers"
/usr/bin/ditto "$ANYWORK_BRIDGE_LIBRARY" "$bridge"
/usr/bin/xcrun install_name_tool -id @rpath/libpl_studio_bridge.dylib "$bridge"
/usr/bin/ditto "$ANYWORK_REMOTE_HELPER_DIR" "$helpers"
# Nested native code must be signed before Xcode signs the outer app.
if [ "${CODE_SIGNING_ALLOWED:-YES}" != "NO" ]; then
  /usr/bin/codesign --force --sign "${EXPANDED_CODE_SIGN_IDENTITY:--}" "$bridge"
fi
