import 'dart:async';

import 'package:flutter/gestures.dart' show DragStartBehavior;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../diagnostics/studio_driver_keys.dart';
import '../../../l10n/studio_l10n.dart';

/// Responsive shell geometry only. Sidebar editing/raw value and its save
/// generation are owned by the VM, never by this focus/drag controller.
class WorkspaceLayoutView extends StatefulWidget {
  const WorkspaceLayoutView({
    required this.sidebar, required this.header, required this.banners,
    required this.content, required this.canonicalSidebarWidth,
    required this.widthDraft, required this.onResizeWidth,
    required this.onResetWidth, required this.onCommitWidth,
    required this.onCancelWidth, super.key,
  });
  final Widget sidebar;
  final Widget header;
  final Widget banners;
  final Widget content;
  final int? canonicalSidebarWidth;
  final double? widthDraft;
  final void Function(double delta, double displayedWidth, double maximumWidth) onResizeWidth;
  final VoidCallback onResetWidth;
  final Future<void> Function() onCommitWidth;
  final VoidCallback onCancelWidth;
  @override
  State<WorkspaceLayoutView> createState() => _WorkspaceLayoutViewState();
}

class _WorkspaceLayoutViewState extends State<WorkspaceLayoutView> {
  static const _dividerWidth = 5.0;
  final _scaffold = GlobalKey<ScaffoldState>();
  final _resizeFocus = FocusNode(debugLabel: 'Sidebar resize');
  bool _hidden = false;
  bool _focused = false;
  bool _dragging = false;

  @override
  void dispose() { _resizeFocus.dispose(); super.dispose(); }

  KeyEventResult _key(KeyEvent event, double width, double maximum) {
    final keyboard = HardwareKeyboard.instance;
    if (event is! KeyUpEvent &&
        (keyboard.isControlPressed || keyboard.isAltPressed || keyboard.isMetaPressed)) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (key != LogicalKeyboardKey.arrowLeft && key != LogicalKeyboardKey.arrowRight &&
        key != LogicalKeyboardKey.home) return KeyEventResult.ignored;
    if (event is KeyUpEvent) {
      unawaited(widget.onCommitWidth());
    } else if (event is KeyDownEvent || event is KeyRepeatEvent) {
      if (key == LogicalKeyboardKey.home) {
        widget.onResetWidth();
      } else {
        widget.onResizeWidth(key == LogicalKeyboardKey.arrowRight ? 16 : -16, width, maximum);
      }
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, constraints) {
    final compact = constraints.maxWidth < 960 || MediaQuery.textScalerOf(context).scale(14) >= 21;
    final overlay = compact || _hidden;
    final maximum = (constraints.maxWidth - 600 - _dividerWidth).clamp(300.0, 440.0).toDouble();
    final width = (widget.widthDraft ?? (widget.canonicalSidebarWidth ?? 336).toDouble())
        .clamp(300.0, maximum).toDouble();
    return Scaffold(
      key: _scaffold,
      drawer: overlay ? Drawer(
        width: (constraints.maxWidth - 24).clamp(0.0, 360.0).toDouble(),
        child: widget.sidebar,
      ) : null,
      body: Row(key: StudioDriverKeys.shell, children: [
        if (!overlay) ...[
          SizedBox(width: width, child: widget.sidebar),
          Focus(
            focusNode: _resizeFocus,
            onFocusChange: (focused) {
              setState(() => _focused = focused);
              if (!focused && !_dragging) unawaited(widget.onCommitWidth());
            },
            onKeyEvent: (_, event) => _key(event, width, maximum),
            child: Semantics(
              key: StudioDriverKeys.sidebarResize, label: context.l10n.sidebarResize,
              slider: true, value: '${width.round()}',
              increasedValue: '${(width + 16).clamp(300, maximum).round()}',
              decreasedValue: '${(width - 16).clamp(300, maximum).round()}',
              onIncrease: () {
                widget.onResizeWidth(16, width, maximum);
                unawaited(widget.onCommitWidth());
              },
              onDecrease: () {
                widget.onResizeWidth(-16, width, maximum);
                unawaited(widget.onCommitWidth());
              },
              child: MouseRegion(cursor: SystemMouseCursors.resizeColumn,
                child: Listener(onPointerUp: (_) => _resizeFocus.requestFocus(),
                  child: GestureDetector(
                    dragStartBehavior: DragStartBehavior.down,
                    onHorizontalDragStart: (_) { _dragging = true; _resizeFocus.requestFocus(); },
                    onHorizontalDragUpdate: (event) => widget.onResizeWidth(event.delta.dx, width, maximum),
                    onHorizontalDragEnd: (_) { _dragging = false; unawaited(widget.onCommitWidth()); },
                    onHorizontalDragCancel: () { _dragging = false; widget.onCancelWidth(); },
                    onDoubleTap: () { widget.onResetWidth(); unawaited(widget.onCommitWidth()); },
                    child: ColoredBox(
                      color: _focused ? Theme.of(context).colorScheme.primary
                          : Theme.of(context).colorScheme.outlineVariant,
                      child: const SizedBox(width: _dividerWidth, height: double.infinity),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
        Expanded(child: Column(children: [
          Row(children: [
            IconButton(key: const ValueKey('sidebar-toggle'), tooltip: context.l10n.sidebarNavigation,
              onPressed: () {
                if (overlay) { _scaffold.currentState?.openDrawer(); }
                else { setState(() => _hidden = true); }
              },
              icon: Icon(overlay ? Icons.menu : Icons.chevron_left)),
            if (_hidden && !compact) IconButton(tooltip: context.l10n.sidebarNavigation,
              onPressed: () => setState(() => _hidden = false), icon: const Icon(Icons.chevron_right)),
            Expanded(child: widget.header),
          ]),
          widget.banners,
          const Divider(height: 1),
          Expanded(child: widget.content),
        ])),
      ]),
    );
  });
}
