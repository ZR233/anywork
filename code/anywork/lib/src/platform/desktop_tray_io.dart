import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:tray_manager/tray_manager.dart';

import '../app/studio_host_lifecycle.dart';
import 'error_log.dart';

/// Bundled application artwork used as the Windows notification-area icon.
const String _trayIconAsset = 'assets/branding/anywork-app-icon.png';

/// Owns the Windows system-tray icon and menu.
///
/// Hiding the main window is a visibility operation only: this controller never
/// cancels sessions, closes the AppGraph or starts the exit coordinator. It is
/// also the reserved cross-platform interface: Linux keeps this class as a
/// no-op implementation and continues to exit through its existing native
/// `delete-event` hook.
final class DesktopTrayController {
  DesktopTrayController._();

  static final DesktopTrayController instance = DesktopTrayController._();

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
  bool _exiting = false;
  Future<void>? _starting;
  Future<void>? _disposing;
  bool _exitHookInstalled = false;

  /// Only Windows implements the notification-area host for now.
  bool get supported => Platform.isWindows;

  bool get isActive => _started && _trayIcon != null;

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
    final attempt = _start(
      tooltip: tooltip,
      showLabel: showLabel,
      exitLabel: exitLabel,
    );
    _starting = attempt;
    return attempt.whenComplete(() {
      if (identical(_starting, attempt)) _starting = null;
    });
  }

  Future<void> showWindow() async {
    if (!supported) return;
    // The native host restores the existing window; it never reinitializes the
    // AppGraph or resumes/cancels any session work.
    await StudioHostLifecycle.showMainWindow();
  }

  Future<void> exit() async {
    if (_exiting) return;
    _exiting = true;
    // Remove the icon before termination so Explorer does not keep a ghost.
    await dispose(notifyNative: true);
    await StudioExitCoordinator.requestExit();
  }

  /// Releases the tray icon. Safe to call repeatedly and from the exit hook.
  Future<void> dispose({bool notifyNative = true}) {
    if (_disposing case final disposing?) return disposing;
    final future = _dispose(notifyNative: notifyNative);
    _disposing = future;
    return future.whenComplete(() {
      if (identical(_disposing, future)) _disposing = null;
    });
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
          unawaited(showWindow());
        }
      });
      exitListener = exitItem.addListener((event) {
        if (event is! MenuItemClickedEvent) return;
        // Run after the native menu has finished closing; disposing the tray
        // from inside its own click callback is not safe.
        Timer.run(() => unawaited(exit()));
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
          unawaited(showWindow());
        }
      });
      if (!trayIcon.setVisible(true)) {
        throw StateError('the native tray icon could not be shown');
      }

      // Only after the icon is really visible may native WM_CLOSE hide instead
      // of entering the exit coordinator.
      await StudioHostLifecycle.setTrayAvailable(true);
      if (_disposed) {
        await StudioHostLifecycle.setTrayAvailable(false);
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
        return;
      }

      _trayIcon = trayIcon;
      _menu = menu;
      _showItem = showItem;
      _exitItem = exitItem;
      _image = image;
      _trayListener = trayListener;
      _showListener = showListener;
      _exitListener = exitListener;
      _started = true;

      StudioExitCoordinator.beforeExit = _disposeForExit;
      _exitHookInstalled = true;
      debugPrint('desktop_tray_started');
    } on Object catch (error, stackTrace) {
      debugPrint('desktop_tray_start_failed=$error\n$stackTrace');
      recordDartError(
        error,
        stackTrace,
        stage: 'desktop-tray-start',
        correlationId: newStudioCorrelationId(),
      );
      await StudioHostLifecycle.setTrayAvailable(false);
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
  }

  Future<void> _disposeForExit() => dispose(notifyNative: false);

  Future<void> _dispose({required bool notifyNative}) async {
    _disposed = true;
    if (_exitHookInstalled) {
      _exitHookInstalled = false;
      StudioExitCoordinator.beforeExit = null;
    }
    if (notifyNative && _started) {
      await StudioHostLifecycle.setTrayAvailable(false);
    }
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
