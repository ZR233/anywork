#!/bin/sh
set -eu
mkdir -p /logs/verifier
if [ "$(cat /workspace/task/harbor-result.txt 2>/dev/null)" = ANYWK_HARBOR_OK ]; then
    printf '1\n' > /logs/verifier/reward.txt
else
    printf '0\n' > /logs/verifier/reward.txt
fi
