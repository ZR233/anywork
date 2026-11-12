#!/bin/sh
# Xcode consumes xtask's prebuilt inputs; it never invokes Cargo or cross compilers.
set -eu
app="$TARGET_BUILD_DIR/$CONTENTS_FOLDER_PATH"
bridge="$app/Frameworks/libpl_studio_bridge.dylib"
helpers="$app/Resources/data/remote-helper"
host_mcp="$app/Resources/data/host-mcp"
licenses="$app/Resources/licenses"
mkdir -p "$licenses"
/usr/bin/ditto "$PROJECT_DIR/LICENSE.flutter" "$licenses/LICENSE.flutter"
/usr/bin/ditto "$PROJECT_DIR/../../../LICENSE" "$licenses/LICENSE.anywork"
/usr/bin/ditto "$PROJECT_DIR/../../pl-studio-runtime/THIRD_PARTY_NOTICES.md" "$licenses/THIRD_PARTY_NOTICES.md"
if [ "${ANYWORK_DEMO:-}" = "true" ]; then
  rm -f "$bridge"
  rm -rf "$helpers"
  rm -rf "$host_mcp"
  exit 0
fi
: "${ANYWORK_BRIDGE_LIBRARY:?Run cargo xtask build-gui or run-gui to build the Rust bridge}"
: "${ANYWORK_REMOTE_HELPER_DIR:?xtask must prepare bundled remote helpers}"
: "${ANYWORK_HOST_MCP_DIR:?xtask must prepare native Host MCP resources}"
case "${ANYWORK_MACOS_ARCH:?xtask must select the native architecture}" in
  arm64) host_mcp_target=aarch64-apple-darwin ;;
  x86_64) host_mcp_target=x86_64-apple-darwin ;;
  *) echo "Unsupported Host MCP architecture: $ANYWORK_MACOS_ARCH" >&2; exit 1 ;;
esac
case "$ANYWORK_HOST_MCP_DIR" in
  /*) ;;
  *) echo "ANYWORK_HOST_MCP_DIR must be absolute" >&2; exit 1 ;;
esac
test -f "$ANYWORK_HOST_MCP_DIR/$host_mcp_target/pl-studio-mcp.zst"
test -f "$ANYWORK_HOST_MCP_DIR/$host_mcp_target/pl-studio-mcp.metadata.json"
test -f "$ANYWORK_BRIDGE_LIBRARY"
for target in aarch64-unknown-linux-musl x86_64-unknown-linux-musl; do
  test -f "$ANYWORK_REMOTE_HELPER_DIR/$target/pl-remote-helper.zst"
  test -f "$ANYWORK_REMOTE_HELPER_DIR/$target/pl-remote-helper.metadata.json"
done
mkdir -p "$app/Frameworks" "$helpers"
/usr/bin/ditto "$ANYWORK_BRIDGE_LIBRARY" "$bridge"
/usr/bin/xcrun install_name_tool -id @rpath/libpl_studio_bridge.dylib "$bridge"
/usr/bin/ditto "$ANYWORK_REMOTE_HELPER_DIR" "$helpers"
mkdir -p "$host_mcp/$host_mcp_target"
/usr/bin/ditto "$ANYWORK_HOST_MCP_DIR/$host_mcp_target" "$host_mcp/$host_mcp_target"
# Nested native code must be signed before Xcode signs the outer app.
if [ "${CODE_SIGNING_ALLOWED:-YES}" != "NO" ]; then
  /usr/bin/codesign --force --sign "${EXPANDED_CODE_SIGN_IDENTITY:--}" "$bridge"
fi
