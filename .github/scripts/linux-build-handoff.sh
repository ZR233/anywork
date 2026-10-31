#!/usr/bin/env bash
# GitHub-only adaptation of immutable image or same-run candidate outputs.
set -euo pipefail

if [ -n "${LINUX_IMAGE_REF:-}" ]; then
  [[ "$LINUX_IMAGE_REF" =~ ^ghcr\.io/zr233/anywork-linux-build@sha256:[0-9a-f]{64}$ ]]
  docker pull "$LINUX_IMAGE_REF"
  image="$LINUX_IMAGE_REF"
else
  [[ "${LINUX_IMAGE_ARTIFACT_ID:-}" =~ ^[1-9][0-9]*$ ]]
  [[ "${LINUX_IMAGE_ARCHIVE_SHA256:-}" =~ ^[0-9a-f]{64}$ ]]
  [[ "${LINUX_IMAGE_ID:-}" =~ ^sha256:[0-9a-f]{64}$ ]]
  archive="$RUNNER_TEMP/linux-build-image/linux-build-image.tar"
  echo "$LINUX_IMAGE_ARCHIVE_SHA256  $archive" | sha256sum --check --strict
  docker load --input "$archive"
  test "$(docker image inspect --format '{{.Id}}' "$LINUX_IMAGE_ID")" = "$LINUX_IMAGE_ID"
  image="$LINUX_IMAGE_ID"
fi

key="$(python3 docker/linux/scripts/image-key.py)"
actual="$(docker image inspect --format '{{index .Config.Labels "io.anywork.build-inputs"}}' "$image")"
test "$actual" = "$key"
echo "LINUX_BUILD_IMAGE=$image" >> "$GITHUB_ENV"
