#!/usr/bin/env bash
# Runs as root only inside a disposable, clean distribution container.
set -euo pipefail
if (( $# != 2 )); then
  echo "Usage: $0 PACKAGE VERSION" >&2
  exit 2
fi
package=$(realpath -e -- "$1")
version=$2
[[ "$version" =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]]
test "$(dpkg-deb -f "$package" Package)" = anywork
test "$(dpkg-deb -f "$package" Architecture)" = amd64
test "$(dpkg-deb -f "$package" Version)" = "$version"
export DEBIAN_FRONTEND=noninteractive
mkdir -p /evidence
exec > >(tee /evidence/smoke.log) 2>&1
cat /etc/os-release

# Install the product alone first: test tools must not mask missing Depends.
apt-get update
apt-get install -y --no-install-recommends "$package"
test "$(dpkg-query -W -f='${Architecture} ${Version} ${Status}' anywork)" = \
  "amd64 $version install ok installed"
# libepoxy loads these APIs dynamically, outside DT_NEEDED. Verify that product
# Depends installed them before inspection tools or software drivers are added.
for runtime in libegl1 libgl1 libgles2; do
  test "$(dpkg-query -W -f='${Status}' "$runtime")" = "install ok installed"
done
test -z "$(dpkg --audit)"
test "$(readlink /usr/bin/anywork)" = /opt/anywork/anywork
test -x /usr/bin/anywork
test -s /usr/share/applications/io.github.zr233.anywork.desktop
test -s /usr/share/icons/hicolor/1024x1024/apps/io.github.zr233.anywork.png
test -s /opt/anywork/LICENSE
test -s /opt/anywork/THIRD_PARTY_NOTICES.md
for target in x86_64-unknown-linux-musl aarch64-unknown-linux-musl; do
  test -s "/opt/anywork/data/remote-helper/$target/pl-remote-helper.zst"
  test -s "/opt/anywork/data/remote-helper/$target/pl-remote-helper.metadata.json"
done

# ldd is supplied by libc-bin, not by the later validation packages.
elfs=()
while IFS= read -r -d '' file; do
  magic=$(od -An -tx1 -N4 "$file" | tr -d ' \n')
  if [[ "$magic" = 7f454c46 ]]; then
    elfs+=("$file")
    echo "Checking runtime loader before test-tool installation: $file"
    status=0
    if [[ "$file" = /opt/anywork/anywork ]]; then
      report=$(env -u LD_LIBRARY_PATH -u LD_PRELOAD ldd -r "$file" 2>&1) || status=$?
    else
      # Standalone analysis simulates the bundle-private libraries already loaded
      # by main. This command-only path is not a product startup wrapper.
      report=$(env -u LD_PRELOAD LD_LIBRARY_PATH=/opt/anywork/lib ldd -r "$file" 2>&1) || status=$?
    fi
    printf '%s\n' "$report"
    if grep -Eq 'not found|undefined symbol|version .* not found' <<< "$report"; then
      exit 1
    fi
    if (( status != 0 )) && ! grep -Eq 'not a dynamic executable|statically linked' <<< "$report"; then
      exit "$status"
    fi
  fi
done < <(find /opt/anywork -type f -print0)
(( ${#elfs[@]} > 0 ))

# Only inspection/headless rendering utilities, never a development toolchain.
apt-get install -y --no-install-recommends \
  binutils xvfb xauth dbus-x11 libgl1-mesa-dri libglx-mesa0 x11-utils
for file in "${elfs[@]}"; do
  echo "ELF ABI evidence: $file"
  readelf --file-header --version-info "$file"
done > /evidence/elf-versions.log

export HOME=/tmp/anywork-smoke/home
export ANYWORK_HOME=/tmp/anywork-smoke/data
export XDG_CONFIG_HOME=/tmp/anywork-smoke/config
export XDG_DATA_HOME=/tmp/anywork-smoke/share
export XDG_CACHE_HOME=/tmp/anywork-smoke/cache
export XDG_RUNTIME_DIR=/tmp/anywork-smoke/runtime
mkdir -p "$HOME" "$ANYWORK_HOME" "$XDG_CONFIG_HOME" "$XDG_DATA_HOME" "$XDG_CACHE_HOME" "$XDG_RUNTIME_DIR"
chmod 700 "$XDG_RUNTIME_DIR"
export GDK_BACKEND=x11 LIBGL_ALWAYS_SOFTWARE=1 LANG=C.UTF-8
unset LD_LIBRARY_PATH LD_PRELOAD

# A new process group owns Xvfb, D-Bus, the GUI, and any workers. Reap the
# session leader here; docker --init reaps adopted grandchildren on container exit.
session=
cleanup() {
  local status=$?
  trap - EXIT INT TERM
  if [[ -n "$session" ]]; then
    kill -TERM -- "-$session" 2>/dev/null || true
    for _ in {1..50}; do
      if ! kill -0 -- "-$session" 2>/dev/null; then break; fi
      sleep 0.1
    done
    kill -KILL -- "-$session" 2>/dev/null || true
    wait "$session" 2>/dev/null || true
  fi
  exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
setsid xvfb-run -a -s '-screen 0 1280x720x24' dbus-run-session -- bash -euo pipefail -c '
  anywork > /evidence/application.log 2>&1 &
  app=$!
  trap '\''kill "$app" 2>/dev/null || true; wait "$app" 2>/dev/null || true'\'' EXIT
  for _ in {1..120}; do
    kill -0 "$app"
    xwininfo -root -tree > /evidence/windows.log
    while read -r window; do
      pid=$(xprop -id "$window" _NET_WM_PID)
      if [[ "$pid" = "_NET_WM_PID(CARDINAL) = $app" ]] &&
          xwininfo -id "$window" | grep -q "Map State: IsViewable"; then
        # Native runner maps this window only after Flutter emits first-frame.
        xwininfo -id "$window" > /evidence/first-frame-window.log
        xprop -id "$window" > /evidence/window-properties.log
        kill -0 "$app"
        echo "PASS: installed application rendered its first visible Flutter window"
        exit 0
      fi
    done < <(awk '\''$1 ~ /^0x/ {print $1}'\'' /evidence/windows.log)
    sleep 0.5
  done
  echo "No visible application window / first-frame evidence within 60 seconds" >&2
  exit 1
' &
session=$!
wait "$session"
