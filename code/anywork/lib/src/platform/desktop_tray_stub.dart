/// Desktop system-tray integration for hosts without `dart:io`.
///
/// The Windows implementation lives in `desktop_tray_io.dart`; Linux and the
/// web intentionally keep this no-op interface so the app can add a tray host
/// later without changing callers.
final class DesktopTrayController {
  DesktopTrayController._();

  static final DesktopTrayController instance = DesktopTrayController._();

  /// No host in this build provides a desktop tray.
  bool get supported => false;

  bool get isActive => false;

  Future<void> start({
    required String tooltip,
    required String showLabel,
    required String exitLabel,
  }) async {}

  Future<void> showWindow() async {}

  Future<void> exit() async {}

  Future<void> dispose({bool notifyNative = true}) async {}
}
