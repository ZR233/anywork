#!/usr/bin/env bash
set -euo pipefail

directory=target/studio-anywk
case "${RUNNER_OS:?}" in
  Windows) executable=anywk.exe ;;
  Linux|macOS) executable=anywk ;;
  *) printf 'Unsupported anywk runner OS: %s\n' "$RUNNER_OS" >&2; exit 2 ;;
esac

archive_sha256() {
  local digest
  if [[ "$RUNNER_OS" == macOS ]]; then
    digest=$(shasum -a 256)
  else
    digest=$(sha256sum)
  fi
  printf '%s\n' "${digest%% *}"
}

verify_files() {
  test -f "$directory/$executable"
  test ! -L "$directory/$executable"
  test -f "$directory/build-info.json"
  test ! -L "$directory/build-info.json"
  if [[ "$RUNNER_OS" != Windows ]]; then
    test -x "$directory/$executable"
  fi
}

case "${1:-}" in
  checkpoint)
    shopt -s dotglob nullglob
    files=("$directory"/*)
    test "${#files[@]}" -eq 2
    verify_files
    archive="$RUNNER_TEMP/anywk.tar"
    # Stream through Bash redirection so tar never interprets a Windows drive as a remote host.
    COPYFILE_DISABLE=1 tar -cf - -C "$directory" "$executable" build-info.json > "$archive"
    digest=$(archive_sha256 < "$archive")
    printf 'archiveSha256=%s\n' "$digest" >> "$GITHUB_OUTPUT"
    ;;
  restore)
    archive="$RUNNER_TEMP/studio-anywk/anywk.tar"
    if [[ ! "$ANYWK_ARCHIVE_SHA256" =~ ^[0-9a-f]{64}$ ]]; then
      printf 'Missing or malformed producer anywk archive SHA-256\n' >&2
      exit 1
    fi
    if [[ "$(archive_sha256 < "$archive")" != "$ANYWK_ARCHIVE_SHA256" ]]; then
      printf 'SHA-256 mismatch for %s\n' "$archive" >&2
      exit 1
    fi
    expected=$(printf '%s\n%s\n' "$executable" build-info.json | LC_ALL=C sort)
    members=$(tar -tf - < "$archive" | LC_ALL=C sort)
    if [[ "$members" != "$expected" ]]; then
      printf 'Unexpected members in %s\n' "$archive" >&2
      exit 1
    fi
    mkdir -p target
    mkdir "$directory"
    tar -xf - -C "$directory" < "$archive"
    verify_files
    ;;
  *) printf 'Usage: %s {checkpoint|restore}\n' "$0" >&2; exit 2 ;;
esac
