macOS runner based on Flutter 3.47.7's official app template at
`abaf9c523780a608bd46686fd5e53740a07077f8` (BSD-3-Clause):
https://github.com/flutter/flutter/tree/abaf9c523780a608bd46686fd5e53740a07077f8/packages/flutter_tools/templates/app/macos.tmpl

The minimum deployment target is macOS 13, matching the current native code asset toolchain.

The AppKit adapter uses the existing Rust instance lease and shared C++ exit watchdog.
Swift Package Manager integrates all existing desktop plugins. Xcode stages the bridge and Linux SSH
helper resources prepared by xtask; it never compiles Rust. Local builds use ad-hoc signing.
The app runs outside App Sandbox because agent tools require workspace access and child
processes. Developer ID signing, notarization and stable Release distribution are separate
from this local build entrypoint.

AppKit quit requests (including logout/shutdown) return `NSTerminateLater` until
coordinated cleanup completes. The native delegate then acknowledges termination
and preserves the confirmed exit code under the existing hard deadline.
After `cargo xtask build-gui`, run the headless AppKit regression checks with
`python3 .github/scripts/studio-macos-termination-tests.py dist/anywork-release/anywork.app`.
They compile the production adapters and replace only Dart cleanup; no system
logout/shutdown or visible window is requested.
