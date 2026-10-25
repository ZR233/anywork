import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:tray_manager/tray_manager.dart';

import '../app/lifecycle/native_exit_host.dart';
import 'error_log.dart';

/// Bundled application artwork used as the Windows notification-area icon.
const String _trayIconAsset = 'assets/branding/anywork-app-icon.png';

/// Owns the Windows system-tray icon and menu.
///
/// Hiding the main window is a visibility operation only: it never cancels
/// sessions, closes the AppGraph or starts the exit coordinator. Explicit exit
/// requests use the application owner's injected callback. Each application
/// injects its own host; no process-global controller owns these dependencies.
/// This is also the reserved cross-platform interface: Linux keeps this class
/// as a no-op implementation and continues to exit through its existing native
/// `delete-event` hook.
final class DesktopTrayController {
  DesktopTrayController({required this._host, required this._requestExit});

  final NativeExitHost _host;
  final Future<void> Function() _requestExit;

  TrayIcon? _trayIcon;
  Menu? _menu;
  MenuItem? _showItem;
  MenuItem? _exitItem;
  Image? _image;
  ListenerId? _trayListener;
  ListenerId? _showListener;
  ListenerId? _exitListener;
  bool _started = false;
  bool _disposed = false;
  Future<void>? _starting;
  Future<void>? _disposing;
  Future<void>? _exiting;

  /// Only Windows implements the notification-area host for now.
  bool get supported => Platform.isWindows;

  bool get isActive => !_disposed && _started && _trayIcon != null;

  /// Creates the tray icon and menu after the first Flutter frame.
  ///
  /// The icon is only advertised to native as available after it is visible;
  /// until then a window close keeps the existing coordinated exit path.
  Future<void> start({
    required String tooltip,
    required String showLabel,
    required String exitLabel,
  }) {
    if (!supported || _started || _disposed) return Future<void>.value();
    if (_starting case final starting?) return starting;
    late final Future<void> attempt;
    attempt =
        _start(
          tooltip: tooltip,
          showLabel: showLabel,
          exitLabel: exitLabel,
        ).whenComplete(() {
          if (identical(_starting, attempt)) _starting = null;
        });
    _starting = attempt;
    return attempt;
  }

  Future<void> showWindow() async {
    if (!supported) return;
    // The native host restores the existing window; it never reinitializes the
    // AppGraph or resumes/cancels any session work.
    await _host.showMainWindow();
  }

  Future<void> exit() {
    if (!supported) return Future<void>.value();
    return _exiting ??= _exit();
  }

  Future<void> _exit() async {
    try {
      // Remove the icon before termination so Explorer does not keep a ghost.
      await dispose();
    } finally {
      // A shell failure must not prevent the real coordinator from arming the
      // native deadline. Repeated requests join this same attempt, not a retry.
      await _requestExit();
    }
  }

  /// Releases the tray icon, including an in-flight start attempt.
  ///
  /// The application owner also injects this action as its desktop-shell
  /// release callback. Repeated calls share the original result, even on error.
  Future<void> dispose() {
    if (!supported) return Future<void>.value();
    if (_disposing case final disposing?) return disposing;
    _disposed = true;
    final future = _dispose();
    _disposing = future;
    return future;
  }

  Future<void> _start({
    required String tooltip,
    required String showLabel,
    required String exitLabel,
  }) async {
    TrayIcon? trayIcon;
    Menu? menu;
    MenuItem? showItem;
    MenuItem? exitItem;
    Image? image;
    ListenerId? trayListener;
    ListenerId? showListener;
    ListenerId? exitListener;
    try {
      trayIcon = TrayIcon.create();
      if (trayIcon == null) {
        throw StateError('the native tray icon could not be created');
      }
      image = ImageAsset.fromAsset(_trayIconAsset);
      if (image == null) {
        throw StateError('the tray icon asset could not be loaded');
      }
      trayIcon
        ..icon = image
        ..setTooltip(tooltip);

      menu = Menu.create();
      if (menu == null) {
        throw StateError('the tray menu could not be created');
      }
      showItem = MenuItem.createWithLabelAndType(
        showLabel,
        MenuItemType.normal,
      );
      exitItem = MenuItem.createWithLabelAndType(
        exitLabel,
        MenuItemType.normal,
      );
      if (showItem == null || exitItem == null) {
        throw StateError('the tray menu items could not be created');
      }
      showListener = showItem.addListener((event) {
        if (event is MenuItemClickedEvent) {
          _observeAction(showWindow, stage: 'desktop-tray-show-window');
        }
      });
      exitListener = exitItem.addListener((event) {
        if (event is! MenuItemClickedEvent) return;
        // Run after the native menu has finished closing; disposing the tray
        // from inside its own click callback is not safe.
        Timer.run(() => _observeAction(exit, stage: 'desktop-tray-exit'));
      });
      menu
        ..addItem(showItem)
        ..addSeparator()
        ..addItem(exitItem);
      trayIcon
        ..setContextMenu(menu)
        ..setContextMenuTrigger(ContextMenuTrigger.rightClicked);
      trayListener = trayIcon.addListener((event) {
        if (event is TrayIconClickedEvent ||
            event is TrayIconDoubleClickedEvent) {
          _observeAction(showWindow, stage: 'desktop-tray-show-window');
        }
      });
      if (!trayIcon.setVisible(true)) {
        throw StateError('the native tray icon could not be shown');
      }

      // Only after the icon is really visible may native WM_CLOSE hide instead
      // of entering the exit coordinator.
      await _setTrayAvailable(true);

      // Disposal joins this start before releasing its resources, even if it
      // was requested while native was acknowledging tray availability.
      _trayIcon = trayIcon;
      _menu = menu;
      _showItem = showItem;
      _exitItem = exitItem;
      _image = image;
      _trayListener = trayListener;
      _showListener = showListener;
      _exitListener = exitListener;
      _started = true;

      debugPrint('desktop_tray_started');
    } on Object catch (error, stackTrace) {
      debugPrint('desktop_tray_start_failed=$error\n$stackTrace');
      recordDartError(
        error,
        stackTrace,
        stage: 'desktop-tray-start',
        correlationId: newStudioCorrelationId(),
      );
      try {
        // A failed or timed-out enable may still have reached native. Restore
        // close-to-exit before releasing the icon, and surface rollback errors.
        await _setTrayAvailable(false);
      } finally {
        _disposeNative(
          trayIcon: trayIcon,
          menu: menu,
          showItem: showItem,
          exitItem: exitItem,
          image: image,
          trayListener: trayListener,
          showListener: showListener,
          exitListener: exitListener,
        );
      }
      rethrow;
    }
  }

  Future<void> _dispose() async {
    try {
      final starting = _starting;
      if (starting != null) await starting;
      if (!_started) return;
      try {
        await _setTrayAvailable(false);
      } finally {
        _disposeNative(
          trayIcon: _trayIcon,
          menu: _menu,
          showItem: _showItem,
          exitItem: _exitItem,
          image: _image,
          trayListener: _trayListener,
          showListener: _showListener,
          exitListener: _exitListener,
        );
        _trayIcon = null;
        _menu = null;
        _showItem = null;
        _exitItem = null;
        _image = null;
        _trayListener = null;
        _showListener = null;
        _exitListener = null;
        _started = false;
        debugPrint('desktop_tray_disposed');
      }
    } on Object catch (error, stackTrace) {
      recordDartError(
        error,
        stackTrace,
        stage: 'desktop-tray-dispose',
        correlationId: newStudioCorrelationId(),
      );
      rethrow;
    }
  }

  Future<void> _setTrayAvailable(bool available) async {
    try {
      await _host.setTrayAvailable(available);
    } on Object catch (error, stackTrace) {
      // Log before native resource cleanup can itself fail and replace the
      // propagated error. Neither timeout nor channel failure proves fallback.
      recordDartError(
        error,
        stackTrace,
        stage: available ? 'desktop-tray-enable' : 'desktop-tray-disable',
        correlationId: newStudioCorrelationId(),
      );
      rethrow;
    }
  }

  void _observeAction(Future<void> Function() action, {required String stage}) {
    unawaited(
      Future<void>.sync(action).catchError((Object error, StackTrace stack) {
        recordDartError(
          error,
          stack,
          stage: stage,
          correlationId: newStudioCorrelationId(),
        );
      }),
    );
  }

  void _disposeNative({
    required TrayIcon? trayIcon,
    required Menu? menu,
    required MenuItem? showItem,
    required MenuItem? exitItem,
    required Image? image,
    required ListenerId? trayListener,
    required ListenerId? showListener,
    required ListenerId? exitListener,
  }) {
    if (trayIcon != null) {
      if (trayListener != null) trayIcon.removeListener(trayListener);
      trayIcon
        ..setVisible(false)
        ..setContextMenu(null);
      trayIcon.dispose();
    }
    if (menu != null) {
      if (showListener != null) showItem?.removeListener(showListener);
      if (exitListener != null) exitItem?.removeListener(exitListener);
      menu.dispose();
    }
    showItem?.dispose();
    exitItem?.dispose();
    image?.dispose();
  }
}
