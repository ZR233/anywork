#!/usr/bin/env bash
set -euo pipefail
# This is SDK tooling, not a project dependency cache. Keep pub's generated
# package roots public and include the packages they reference in the image.
# Runtime projects retain pub's default cache under their container-only HOME.
export PUB_CACHE=/opt/flutter-pub-cache
export PUB_HOSTED_URL=https://pub.dev
cd /opt/anywork-toolchain
/opt/flutter/bin/dart pub --directory=/opt/flutter/packages/flutter_tools \
    get --enforce-lockfile
chmod -R a+rX /opt/flutter-pub-cache /opt/flutter/packages/flutter_tools/.dart_tool
