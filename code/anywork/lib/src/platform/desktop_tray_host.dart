import 'dart:async';

import 'package:flutter/widgets.dart';

import '../l10n/studio_l10n.dart';
import 'desktop_tray.dart';
import 'error_log.dart';

/// Hosts the desktop tray lifecycle inside the localized MaterialApp tree.
///
/// Widget tests construct `AnyworkApp` with [enabled] false and never touch the
/// native tray; release, demo and Driver entrypoints enable it.
/// The application owner injects the same [controller] used by shell release.
class DesktopTrayHost extends StatefulWidget {
  const DesktopTrayHost({
    required this.controller,
    required this.child,
    required this.enabled,
    super.key,
  });

  final DesktopTrayController controller;
  final Widget child;
  final bool enabled;

  @override
  State<DesktopTrayHost> createState() => _DesktopTrayHostState();
}

class _DesktopTrayHostState extends State<DesktopTrayHost> {
  late final _controller = widget.controller;

  bool get _shouldStart => widget.enabled && _controller.supported;

  @override
  void initState() {
    super.initState();
    if (!_shouldStart) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final l10n = context.l10n;
      unawaited(
        _controller
            .start(
              tooltip: l10n.appTitle,
              showLabel: l10n.trayShowWindow,
              exitLabel: l10n.trayExit,
            )
            .catchError((Object error, StackTrace stackTrace) {
              recordDartError(
                error,
                stackTrace,
                stage: 'desktop-tray-host-start',
                correlationId: newStudioCorrelationId(),
              );
            }),
      );
    });
  }

  @override
  void didUpdateWidget(DesktopTrayHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(widget.controller, _controller)) {
      throw StateError('A mounted tray host cannot change its controller.');
    }
  }

  @override
  void dispose() {
    if (_shouldStart) {
      unawaited(
        _controller.dispose().catchError((Object error, StackTrace stackTrace) {
          recordDartError(
            error,
            stackTrace,
            stage: 'desktop-tray-host-dispose',
            correlationId: newStudioCorrelationId(),
          );
        }),
      );
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
