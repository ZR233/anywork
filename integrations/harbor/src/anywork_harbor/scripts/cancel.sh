#!/bin/sh
# 仅停止此随机运行标识或已验证 session 的进程；不按名称或全局进程组终止。
set -eu
set -f
private=$1
launcher=$2
case "$launcher" in *[!a-f0-9-]*|'') exit 2;; esac
start=$(date +%s%3N)
identity="$private/identity.json"
mismatch=false
error=null
remaining=''
anchor=false
leader=0
sid=0
ticks=0
if [ -f "$identity" ] && [ ! -L "$identity" ]; then
    recorded=$(sed -n 's/.*"launcherId":"\([a-f0-9-]*\)".*/\1/p' "$identity")
    leader=$(sed -n 's/.*"pid":\([0-9]*\),.*/\1/p' "$identity")
    sid=$(sed -n 's/.*"sid":\([0-9]*\),.*/\1/p' "$identity")
    ticks=$(sed -n 's/.*"startTimeTicks":\([0-9]*\).*/\1/p' "$identity")
    [ "$recorded" = "$launcher" ] || mismatch=true
else
    error='"identityMissing"'
fi
case "$leader:$sid:$ticks" in *[!0-9:]*|::*|*:|:*) mismatch=true;; esac
stat_fields() {
    [ -r "/proc/$1/stat" ] || return 1
    IFS= read -r line 2>/dev/null < "/proc/$1/stat" || return 1
    suffix=${line##*) }
    set -- $suffix
    state=$1 actual_sid=$4
    shift 19
    actual_ticks=$1
    [ "$state" != Z ] && [ "$state" != X ]
}
marker() {
    [ -r "/proc/$1/environ" ] || return 1
    grep -Fzxq "ANYWK_HARBOR_RUN_ID=$launcher" "/proc/$1/environ" 2>/dev/null
}
if [ "$mismatch" = false ] && stat_fields "$leader"; then
    if [ "$actual_sid" = "$sid" ] && [ "$actual_ticks" = "$ticks" ] && marker "$leader"; then
        anchor=true
        if stat_fields "$leader" && [ "$actual_ticks" = "$ticks" ]; then
            kill -TERM "$leader" 2>/dev/null || true
        fi
    else
        mismatch=true
    fi
fi
# 保存 PID/starttime 锚点；每次发信号前重新核对，覆盖独立 PGID 和继承标识的独立 SID。
known="$private/cleanup-known"
: > "$known"
known_ids='|'
is_known() {
    case "$known_ids" in *"|$1:$2|"*) return 0;; *) return 1;; esac
}
remember() {
    if ! is_known "$1" "$2"; then
        known_ids="$known_ids$1:$2|"
        printf '%s:%s\n' "$1" "$2" >> "$known"
    fi
}
if [ "$anchor" = true ]; then remember "$leader" "$ticks"; fi
sweep() {
    remaining=''
    # 只重查已知 PID/starttime 锚点，不扫描第二遍 /proc。
    anchor=false
    while IFS=: read -r known_pid known_ticks; do
        if stat_fields "$known_pid" && [ "$actual_ticks" = "$known_ticks" ] && [ "$actual_sid" = "$sid" ]; then
            anchor=true
            break
        fi
    done < "$known"
    # set -f 禁用对 /proc stat 内容的 glob；目录枚举显式启用后立即关闭。
    set +f
    for proc in /proc/[0-9]*; do
        set -f
        pid=${proc##*/}
        [ "$pid" != "$$" ] || continue
        stat_fields "$pid" || continue
        captured=$actual_ticks
        owned=false
        if [ "$anchor" = true ] && [ "$actual_sid" = "$sid" ]; then
            owned=true
        elif is_known "$pid" "$captured"; then
            owned=true
        elif marker "$pid"; then
            owned=true
            if [ "$actual_sid" = "$sid" ]; then anchor=true; fi
        fi
        [ "$owned" = true ] || continue
        remember "$pid" "$captured"
        remaining="${remaining}${remaining:+,}$pid"
        if [ "$1" = KILL ] && stat_fields "$pid" && [ "$actual_ticks" = "$captured" ]; then
            kill -KILL "$pid" 2>/dev/null || true
        fi
    done
    set -f
}
while :; do
    now=$(date +%s%3N)
    elapsed=$((now - start))
    if [ "$elapsed" -ge 3000 ]; then sweep KILL; else sweep CHECK; fi
    [ -n "$remaining" ] || break
    [ "$elapsed" -lt 4500 ] || break
    sleep 0.1
done
sweep CHECK
clean=false
if [ -z "$remaining" ] && [ "$mismatch" = false ] && [ "$error" = null ]; then clean=true; fi
elapsed=$(($(date +%s%3N) - start))
printf '{"attempted":true,"clean":%s,"remainingKnownPids":[%s],"identityMismatch":%s,"elapsedMs":%s,"error":%s}\n' \
    "$clean" "$remaining" "$mismatch" "$elapsed" "$error"
