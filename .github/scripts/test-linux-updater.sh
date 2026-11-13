#!/usr/bin/env bash
# Root package operations are confined to disposable distribution containers.
set -euo pipefail
if (( $# != 1 )); then
  echo 'Usage: test-linux-updater.sh UPDATE_CRATE_TEST_EXECUTABLE' >&2
  exit 2
fi
executable=$(realpath -e -- "$1")
test -x "$executable"
result=0
for runtime in ubuntu:22.04 ubuntu:24.04 debian:12-slim debian:13-slim; do
  image="anywork-updater-test:${runtime//[:.]/-}"
  docker build --platform linux/amd64 --build-arg "BASE_IMAGE=$runtime" --file docker/linux/tests-updater.Dockerfile --tag "$image" .
  if ! docker run --rm --init --platform linux/amd64 --mount "type=bind,src=$executable,dst=/update-tests,readonly" "$image" \
      bash -euo pipefail -c '
        dbus-daemon --system --fork --nopidfile
        exec /update-tests --exact linux::helper::tests::real_packagekit_upgrades_and_preserves_installed_version_on_failure --ignored --nocapture
      '; then
    result=1
  fi
done
exit "$result"
