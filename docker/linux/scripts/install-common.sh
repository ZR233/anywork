#!/usr/bin/env bash
set -euo pipefail
source /opt/anywork-image/versions.env

# No mirror, fallback version, credentials, or unverified executable downloads.
download() {
    local url=$1 digest=$2 destination=$3
    curl --proto '=https' --proto-redir '=https' --tlsv1.2 \
        --fail --location --show-error --silent \
        --connect-timeout 30 --max-time 1800 "$url" --output "$destination"
    printf '%s  %s\n' "$digest" "$destination" | sha256sum --check --strict
}
