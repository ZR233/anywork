#!/usr/bin/env bash
set -euo pipefail
source /opt/anywork-image/scripts/install-common.sh
temporary=$(mktemp -d)
trap 'rm -rf -- "$temporary"' EXIT
download "https://www.kernel.org/pub/software/scm/git/git-${GIT_VERSION}.tar.xz" \
    "$GIT_SHA256" "$temporary/git.tar.xz"
tar -xJf "$temporary/git.tar.xz" -C "$temporary"
cd "$temporary/git-$GIT_VERSION"
# Official Git Makefile installation; retain HTTP(S), SSH and Perl commands.
# Git 2.x supports its C implementation, keeping this stage independent of Rust.
options=(prefix=/opt/git NO_RUST=YesPlease NO_TCLTK=YesPlease NO_GETTEXT=YesPlease PYTHON_PATH=/usr/bin/python3)
make -j2 "${options[@]}" all
make "${options[@]}" install
test "$(/opt/git/bin/git --version)" = "git version $GIT_VERSION"
# Carry the exact corresponding source, license and build inputs with the binary.
mkdir -p /opt/git-source
cp "$temporary/git.tar.xz" /opt/git-source/
cp COPYING /opt/git-source/
cp /opt/anywork-image/scripts/install-{common,git}.sh /opt/git-source/
cp /opt/anywork-image/versions.env /opt/git-source/
