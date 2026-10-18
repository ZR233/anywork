import 'dart:async';

import 'package:flutter/widgets.dart';

import '../l10n/studio_l10n.dart';
import 'desktop_tray.dart';

/// Hosts the desktop tray lifecycle inside the localized MaterialApp tree.
///
/// Widget tests construct `AnyworkApp` with [enabled] false and never touch the
/// native tray; release, demo and Driver entrypoints enable it.
class DesktopTrayHost extends StatefulWidget {
  const DesktopTrayHost({
    required this.child,
    required this.enabled,
    super.key,
  });

  final Widget child;
  final bool enabled;

  @override
  State<DesktopTrayHost> createState() => _DesktopTrayHostState();
}

class _DesktopTrayHostState extends State<DesktopTrayHost> {
  bool get _shouldStart =>
      widget.enabled && DesktopTrayController.instance.supported;

  @override
  void initState() {
    super.initState();
    if (!_shouldStart) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final l10n = context.l10n;
      unawaited(
        DesktopTrayController.instance.start(
          tooltip: l10n.appTitle,
          showLabel: l10n.trayShowWindow,
          exitLabel: l10n.trayExit,
        ),
      );
    });
  }

  @override
  void dispose() {
    if (_shouldStart) {
      unawaited(DesktopTrayController.instance.dispose());
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
