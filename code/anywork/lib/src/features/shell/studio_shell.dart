import 'dart:async';

import 'package:flutter/gestures.dart' show DragStartBehavior;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/theme/studio_tokens.dart';
import '../../diagnostics/studio_driver_keys.dart';
import '../../l10n/studio_l10n.dart';

/// Marks navigation rendered inside the shell's modal drawer so the sidebar can
/// offer the drawer's own close affordance instead of guessing its host.
class ShellDrawerScope extends InheritedWidget {
  const ShellDrawerScope({
    required this.close,
    required super.child,
    super.key,
  });

  final VoidCallback close;

  static ShellDrawerScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ShellDrawerScope>();

  @override
  bool updateShouldNotify(ShellDrawerScope oldWidget) =>
      close != oldWidget.close;
}

/// Dumb application geometry. Workspace supplies its canonical sidebar width,
/// edit draft and save callbacks; shell owns only focus/drag/drawer state.
/// [workspace] is the existing ConversationScreen or Workspace start content,
/// preserving its status, timeline, interaction, Send and independent Stop.
class AppShell extends StatefulWidget {
  const AppShell({
    required this.navigation,
    required this.chrome,
    required this.notices,
    required this.workspace,
    required this.canonicalSidebarWidth,
    required this.widthDraft,
    required this.onResizeWidth,
    required this.onResetWidth,
    required this.onCommitWidth,
    required this.onCancelWidth,
    super.key,
  });

  final Widget navigation;
  final Widget chrome;
  final Widget notices;
  final Widget workspace;
  final int? canonicalSidebarWidth;
  final double? widthDraft;
  final void Function(double delta, double displayedWidth, double maximumWidth)
  onResizeWidth;
  final VoidCallback onResetWidth;
  final Future<void> Function() onCommitWidth;
  final VoidCallback onCancelWidth;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  final _scaffold = GlobalKey<ScaffoldState>();
  final _resizeFocus = FocusNode(debugLabel: 'Application navigation resize');
  bool _collapsed = false;
  bool _resizing = false;
  bool _dividerFocused = false;
  static const _dividerWidth = 5.0;

  @override
  void dispose() {
    _resizeFocus.dispose();
    super.dispose();
  }

  void _commit() => unawaited(widget.onCommitWidth());

  void _resize(double delta, double width, double maximum) =>
      widget.onResizeWidth(delta, width, maximum);

  KeyEventResult _resizeKey(KeyEvent event, double width, double maximum) {
    final key = event.logicalKey;
    final keyboard = HardwareKeyboard.instance;
    if ((keyboard.isControlPressed ||
            keyboard.isAltPressed ||
            keyboard.isMetaPressed) &&
        event is! KeyUpEvent) {
      return KeyEventResult.ignored;
    }
    if (key != LogicalKeyboardKey.arrowLeft &&
        key != LogicalKeyboardKey.arrowRight &&
        key != LogicalKeyboardKey.home) {
      return KeyEventResult.ignored;
    }
    if (event is KeyUpEvent) {
      _commit();
    } else if (event is KeyDownEvent || event is KeyRepeatEvent) {
      if (key == LogicalKeyboardKey.home) {
        widget.onResetWidth();
      } else {
        _resize(
          key == LogicalKeyboardKey.arrowRight ? 16 : -16,
          width,
          maximum,
        );
      }
    }
    return KeyEventResult.handled;
  }

  Widget _divider(BuildContext context, double width, double maximum) => Focus(
    focusNode: _resizeFocus,
    onFocusChange: (focused) {
      setState(() => _dividerFocused = focused);
      if (!focused && !_resizing) _commit();
    },
    onKeyEvent: (_, event) => _resizeKey(event, width, maximum),
    child: Semantics(
      key: StudioDriverKeys.sidebarResize,
      label: context.l10n.sidebarResize,
      slider: true,
      value: '${width.round()}',
      increasedValue: '${(width + 16).clamp(300, maximum).round()}',
      decreasedValue: '${(width - 16).clamp(300, maximum).round()}',
      onIncrease: () {
        _resize(16, width, maximum);
        _commit();
      },
      onDecrease: () {
        _resize(-16, width, maximum);
        _commit();
      },
      child: MouseRegion(
        cursor: SystemMouseCursors.resizeColumn,
        child: Listener(
          onPointerUp: (_) => _resizeFocus.requestFocus(),
          child: GestureDetector(
            dragStartBehavior: DragStartBehavior.down,
            onHorizontalDragStart: (_) {
              _resizing = true;
              _resizeFocus.requestFocus();
            },
            onHorizontalDragUpdate: (details) =>
                _resize(details.delta.dx, width, maximum),
            onHorizontalDragEnd: (_) {
              _resizing = false;
              _commit();
            },
            onHorizontalDragCancel: () {
              _resizing = false;
              widget.onCancelWidth();
            },
            onDoubleTap: () {
              widget.onResetWidth();
              _commit();
            },
            child: ColoredBox(
              color: _dividerFocused
                  ? context.colors.primary
                  : context.colors.outlineVariant.withValues(alpha: .5),
              child: const SizedBox(
                width: _dividerWidth,
                height: double.infinity,
              ),
            ),
          ),
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final compact =
          constraints.maxWidth < StudioLayout.compactBreakpoint ||
          MediaQuery.textScalerOf(context).scale(14) >= 21;
      final overlay = compact || _collapsed;
      final maximum = (constraints.maxWidth - 600 - _dividerWidth)
          .clamp(300.0, 440.0)
          .toDouble();
      final width =
          (widget.widthDraft ??
                  (widget.canonicalSidebarWidth ?? 336).toDouble())
              .clamp(300.0, maximum)
              .toDouble();
      return Scaffold(
        key: _scaffold,
        backgroundColor: context.colors.surface,
        drawer: overlay
            ? Drawer(
                width: (constraints.maxWidth - 24).clamp(0.0, 360.0).toDouble(),
                child: ShellDrawerScope(
                  close: () => _scaffold.currentState?.closeDrawer(),
                  child: widget.navigation,
                ),
              )
            : null,
        body: Row(
          key: StudioDriverKeys.shell,
          children: [
            if (!overlay) ...[
              SizedBox(width: width, child: widget.navigation),
              _divider(context, width, maximum),
            ],
            Expanded(
              child: Column(
                children: [
                  Row(
                    children: [
                      IconButton(
                        key: const ValueKey('sidebar-toggle'),
                        tooltip: context.l10n.sidebarNavigation,
                        onPressed: () {
                          if (overlay) {
                            _scaffold.currentState?.openDrawer();
                          } else {
                            setState(() => _collapsed = true);
                          }
                        },
                        icon: Icon(overlay ? Icons.menu : Icons.chevron_left),
                      ),
                      if (_collapsed && !compact)
                        IconButton(
                          tooltip: context.l10n.sidebarNavigation,
                          onPressed: () => setState(() => _collapsed = false),
                          icon: const Icon(Icons.chevron_right),
                        ),
                      Expanded(child: widget.chrome),
                    ],
                  ),
                  widget.notices,
                  const Divider(height: 1),
                  Expanded(child: widget.workspace),
                ],
              ),
            ),
          ],
        ),
      );
    },
  );
}
