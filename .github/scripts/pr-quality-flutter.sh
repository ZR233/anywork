#!/usr/bin/env bash
set -euo pipefail

client=false
app=false
if (( $# == 0 )); then
  client=true
  app=true
fi
for option in "$@"; do
  case "$option" in
    --client) client=true ;;
    --app) app=true ;;
    *)
      printf 'usage: bash .github/scripts/pr-quality-flutter.sh [--client] [--app]\n' >&2
      exit 64
      ;;
  esac
done

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"

run() {
  printf '\n==> %s\n' "$*"
  "$@"
}

printf '\n==> Required lockfiles and nonempty test suites\n'
python3 - "$root" "$client" "$app" <<'PY'
import sys
from pathlib import Path

root = Path(sys.argv[1])
suites = []
if sys.argv[2] == "true":
    suites.append(("code/anywork_client", "test"))
if sys.argv[3] == "true":
    suites.extend([("code/anywork", "test/unit"), ("code/anywork", "test/ui")])
for package, suite in suites:
    directory = root / package
    lockfile = directory / "pubspec.lock"
    if not lockfile.is_file():
        sys.exit(f"required lockfile is missing: {lockfile}")
    tests = directory / suite
    if not tests.is_dir():
        sys.exit(f"required test directory is missing: {tests}")
    count = sum(file.is_file() for file in tests.rglob("*_test.dart"))
    if count == 0:
        sys.exit(f"required test suite has no *_test.dart files: {tests}")
    print(f"{package}/{suite}: discovered {count} test files")
PY

if "$client"; then
cd -- "$root/code/anywork_client"
run dart pub get --enforce-lockfile
printf '\n==> Client SDK-only runtime dependency boundary\n'
# JSON includes dev dependencies; directDependencies identifies runtime edges.
# Do not combine --json with --no-dev: the official CLI rejects that pairing.
dart pub deps --json | python3 -c '
import json
import sys

def fail(message):
    sys.exit(f"Client SDK-only boundary failed: {message}")

data = json.load(sys.stdin)
if not isinstance(data, dict) or data.get("root") != "anywork_client":
    fail("root must be anywork_client")
packages = data.get("packages")
if not isinstance(packages, list) or not all(isinstance(p, dict) for p in packages):
    fail("packages must be an array of objects")
roots = [p for p in packages if p.get("kind") == "root"]
if len(roots) != 1 or roots[0].get("name") != "anywork_client":
    fail("expected exactly one root package named anywork_client")
dependencies = roots[0].get("directDependencies")
if not isinstance(dependencies, list) or dependencies:
    fail("root directDependencies must exist and be an empty array")
print("Client SDK-only runtime dependency boundary passed")
'
run dart format --output=none --set-exit-if-changed lib test
run dart analyze --fatal-infos
run dart test --reporter=expanded
fi

if "$app"; then
cd -- "$root/code/anywork"
run flutter pub get --enforce-lockfile
run dart format --output=none --set-exit-if-changed lib test tool integration_test
run flutter analyze --no-pub
run dart --packages=.dart_tool/package_config.json \
  ../../xtask/dart/client_boundary_check.dart "$root"
run dart --packages=.dart_tool/package_config.json \
  ../../xtask/dart/client_boundary_check.dart --ui-closure "$root"
run flutter test --no-pub test/unit test/ui
fi
