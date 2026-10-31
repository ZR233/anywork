#!/usr/bin/env bash
# Host-side CI checkpoints. All container inputs stay inside the mounted checkout.
set -euo pipefail

artifact_ids() {
  (( $# > 0 ))
  for id in "$@"; do
    [[ "$id" =~ ^[1-9][0-9]*$ ]] || { echo "Invalid producer artifact ID: $id" >&2; exit 1; }
  done
}

verify_sha() {
  [[ "$2" =~ ^[0-9a-f]{64}$ ]]
  printf '%s  %s\n' "$2" "$1" | sha256sum --check --strict
}

output_sha() {
  local digest
  digest=$(sha256sum "$2")
  printf '%s=%s\n' "$1" "${digest%% *}" >> "$GITHUB_OUTPUT"
}

version() {
  [[ "$RELEASE_VERSION" =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]]
}

case "${1:-}" in
  artifact-ids)
    shift
    artifact_ids "$@"
    ;;
  checkpoint)
    tar -czf "$RUNNER_TEMP/linux-bundle.tar.gz" -C dist/anywork-release .
    tar -czf "$RUNNER_TEMP/linux-tool.tar.gz" -C target/xtask/debug pl-xtask
    output_sha bundleSha256 "$RUNNER_TEMP/linux-bundle.tar.gz"
    output_sha toolSha256 "$RUNNER_TEMP/linux-tool.tar.gz"
    printf 'toolWorkspace=%s\n' "$(pwd -P)" >> "$GITHUB_OUTPUT"
    ;;
  restore-inputs)
    artifact_ids "$BUNDLE_ARTIFACT_ID" "$TOOL_ARTIFACT_ID"
    test "$(pwd -P)" = "$TOOL_WORKSPACE"
    verify_sha "$RUNNER_TEMP/linux-bundle/linux-bundle.tar.gz" "$BUNDLE_SHA256"
    verify_sha "$RUNNER_TEMP/linux-tool/linux-tool.tar.gz" "$TOOL_SHA256"
    destination="$GITHUB_WORKSPACE/target/linux-handoff"
    test ! -e "$destination"
    mkdir -p "$destination/bundle" "$destination/tool"
    tar -xzf "$RUNNER_TEMP/linux-bundle/linux-bundle.tar.gz" -C "$destination/bundle"
    tar -xzf "$RUNNER_TEMP/linux-tool/linux-tool.tar.gz" -C "$destination/tool"
    test -x "$destination/tool/pl-xtask"
    printf 'STUDIO_LINUX_BUNDLE=%s/bundle\nSTUDIO_LINUX_TOOL=%s/tool/pl-xtask\n' \
      "$destination" "$destination" >> "$GITHUB_ENV"
    ;;
  archive-assets)
    version
    directory="dist/studio-release/$RELEASE_VERSION"
    name="anywork-$RELEASE_VERSION-linux-x86_64.deb"
    tar -czf "$RUNNER_TEMP/linux-assets.tar.gz" -C "$directory" "$name" "$name.sha256"
    output_sha archiveSha256 "$RUNNER_TEMP/linux-assets.tar.gz"
    ;;
  restore-assets)
    version
    artifact_ids "$ASSET_ARTIFACT_ID"
    archive="$RUNNER_TEMP/linux-assets/linux-assets.tar.gz"
    verify_sha "$archive" "$ASSET_SHA256"
    name="anywork-$RELEASE_VERSION-linux-x86_64.deb"
    expected=$(printf '%s\n%s\n' "$name" "$name.sha256" | LC_ALL=C sort)
    test "$(tar -tzf "$archive" | LC_ALL=C sort)" = "$expected"
    destination="$GITHUB_WORKSPACE/dist/studio-release/$RELEASE_VERSION"
    test ! -e "$destination"
    mkdir -p "$destination"
    tar -xzf "$archive" -C "$destination"
    test -f "$destination/$name" && test ! -L "$destination/$name"
    test -f "$destination/$name.sha256" && test ! -L "$destination/$name.sha256"
    actual=$(sha256sum "$destination/$name")
    printf '%s  %s\n' "${actual%% *}" "$name" > "$RUNNER_TEMP/linux-expected.sha256"
    cmp "$RUNNER_TEMP/linux-expected.sha256" "$destination/$name.sha256"
    ;;
  *)
    echo "Usage: $0 {artifact-ids ID...|checkpoint|restore-inputs|archive-assets|restore-assets}" >&2
    exit 2
    ;;
esac
