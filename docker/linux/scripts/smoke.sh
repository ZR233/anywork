#!/usr/bin/env bash
set -euo pipefail
source /opt/anywork-image/versions.env
temporary=$(mktemp -d "${TMPDIR:-/tmp}/anywork-linux-smoke.XXXXXXXX")
trap 'rm -rf -- "$temporary"' EXIT
cp /opt/anywork-toolchain/rust-toolchain.toml "$temporary/rust-toolchain.toml"
cd "$temporary"

rustup show
rustc --version
cargo --version
rustfmt --version
cargo clippy --version
rust-analyzer --version
test "$(zig version)" = "$ZIG_VERSION"
test "$(cargo binstall -V)" = "$CARGO_BINSTALL_VERSION"
cargo-zigbuild --version | grep -Fx "cargo-zigbuild $CARGO_ZIGBUILD_VERSION"
flutter --version
dart --version
for tool in clang clang++ cmake ninja pkg-config dpkg-deb dpkg-shlibdeps \
    desktop-file-validate xvfb-run dbus-run-session; do
    command -v "$tool"
done
cat > main.rs <<'RUST'
fn main() {
    println!("rust-host-ok");
}
RUST
rustfmt --check main.rs
rustc main.rs -o host
test "$(./host)" = rust-host-ok
for target in aarch64-unknown-linux-musl x86_64-unknown-linux-musl; do
    rustup target list --installed | grep -Fx "$target"
    rustc --target "$target" --emit=obj main.rs -o "$target.o"
    test -s "$target.o"
done
mkdir src
cp main.rs src/main.rs
cat > Cargo.toml <<'TOML'
[package]
name = "anywork-environment-smoke"
version = "0.0.0"
edition = "2021"
TOML
cargo clippy --offline -- -D warnings

cat > CMakeLists.txt <<'CMAKE'
cmake_minimum_required(VERSION 3.16)
project(environment_smoke LANGUAGES CXX)
find_package(PkgConfig REQUIRED)
pkg_check_modules(GTK REQUIRED IMPORTED_TARGET gtk+-3.0)
add_executable(gtk-smoke main.cpp)
target_link_libraries(gtk-smoke PRIVATE PkgConfig::GTK)
CMAKE
cat > main.cpp <<'CPP'
#include <gtk/gtk.h>
#include <iostream>
int main() {
    std::cout << gtk_get_major_version() << '\n';
    return gtk_get_major_version() == 3 ? 0 : 1;
}
CPP
cmake -S . -B native-build -G Ninja -DCMAKE_CXX_COMPILER=clang++
cmake --build native-build
./native-build/gtk-smoke
python3 - <<'PYTHON'
import ctypes
import os
from pathlib import Path

libc = ctypes.CDLL(None, use_errno=True)
libc.prctl.argtypes = [
    ctypes.c_int, ctypes.c_ulong, ctypes.c_ulong, ctypes.c_ulong, ctypes.c_ulong
]
libc.prctl.restype = ctypes.c_int
# PR_SET_CHILD_SUBREAPER requires no capability or privileged container.
if libc.prctl(36, 1, 0, 0, 0) != 0:
    raise OSError(ctypes.get_errno(), "PR_SET_CHILD_SUBREAPER")
assert Path("/proc/self/status").is_file()
assert Path(f"/proc/{os.getpid()}/stat").read_text()
child = os.fork()
if child == 0:
    grandchild = os.fork()
    os._exit(0 if grandchild else 7)
assert os.waitpid(child, 0)[1] == 0
adopted, status = os.waitpid(-1, 0)
assert adopted > 0 and os.waitstatus_to_exitcode(status) == 7
print("subreaper-and-proc-ok")
PYTHON
printf 'Linux environment smoke passed.\n'
