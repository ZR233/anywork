#!/usr/bin/env bash
# Root package operations are confined to disposable distribution containers.
set -euo pipefail
if (( $# != 1 )); then
  echo 'Usage: test-linux-updater.sh UPDATE_CRATE_TEST_EXECUTABLE' >&2
  exit 2
fi
executable=$(realpath -e -- "$1")
test -x "$executable"
logs=$(mktemp -d)
cleanup() {
  rm -rf -- "$logs"
}
trap cleanup EXIT

runtimes=(ubuntu:22.04 ubuntu:24.04 debian:12-slim debian:13-slim)
pids=()
for runtime in "${runtimes[@]}"; do
  slug=${runtime//[:.]/-}
  image="anywork-updater-test:$slug"
  log="$logs/$slug.log"
  (
    printf 'PackageKit verification: %s\n' "$runtime"
    docker build --quiet --platform linux/amd64 --build-arg "BASE_IMAGE=$runtime" --file docker/linux/tests-updater.Dockerfile --tag "$image" .
    docker run --rm --init --platform linux/amd64 --mount "type=bind,src=$executable,dst=/update-tests,readonly" "$image" \
        bash -euo pipefail -c '
          dbus-daemon --system --fork --nopidfile
          exec /update-tests --exact linux::helper::tests::real_packagekit_upgrades_and_preserves_installed_version_on_failure --ignored --nocapture
        '
  ) >"$log" 2>&1 &
  pids+=("$!")
done

result=0
for index in "${!runtimes[@]}"; do
  runtime=${runtimes[$index]}
  slug=${runtime//[:.]/-}
  if ! wait "${pids[$index]}"; then
    result=1
  fi
  cat -- "$logs/$slug.log"
done
exit "$result"
