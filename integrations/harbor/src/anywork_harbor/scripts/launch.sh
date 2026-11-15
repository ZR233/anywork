#!/bin/sh
set -eu
set -f
private=$1
launcher=$2
shift 2
case "$launcher" in *[!a-f0-9-]*|'') exit 2;; esac
[ "${ANYWK_HARBOR_RUN_ID:-}" = "$launcher" ] || exit 2
fields() {
    line=$(cat "/proc/$$/stat")
    suffix=${line##*) }
    set -- $suffix
    pgid=$3 sid=$4
    shift 19
    printf '%s %s %s\n' "$pgid" "$sid" "$1"
}
identity=$(fields)
IFS=' ' read -r pgid sid ticks <<EOF
$identity
EOF
umask 077
printf '{"launcherId":"%s","pid":%s,"pgid":%s,"sid":%s,"startTimeTicks":%s}\n' \
    "$launcher" "$$" "$pgid" "$sid" "$ticks" > "$private/identity.json.tmp"
mv "$private/identity.json.tmp" "$private/identity.json"
exec "$@"
