#!/bin/sh
set -eu
/opt/fixture/pl-provider-fixture --harbor-smoke --harbor-case "${HARBOR_FIXTURE_CASE:-file}" > /tmp/harbor-fixture.log 2>&1 &
fixture=$!
trap 'kill -INT "$fixture" 2>/dev/null || true; wait "$fixture" || true' EXIT INT TERM
i=0
until grep -q '^harbor_fixture_ready=' /tmp/harbor-fixture.log; do
    kill -0 "$fixture"
    i=$((i + 1))
    [ "$i" -lt 100 ] || exit 1
    sleep 0.1
done
"$@"
