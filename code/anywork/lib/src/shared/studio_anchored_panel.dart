import 'dart:async';

import 'package:flutter/material.dart';

/// Anchored free-content panel for readouts and detail views.
///
/// The panel rides on Material's [MenuAnchor]: anchoring, positioning, window
/// clamping, the menu panel's bounded scrolling, outside-tap dismissal and
/// closes on ancestor scrolls or view-size changes are framework behavior.
/// Opening is pointer-driven without installing a second focus or keyboard
/// state machine around the trigger.
///
/// What remains here is the panel's business interaction, following the
/// legacy status details: hovering the trigger shows the panel transiently
/// (hidden after [hideDelay] once the pointer has left), clicking
/// toggles it, and a [pinOpenOnTap] trigger keeps an open panel open under the
/// pointer instead of toggling it closed. After a click closes the panel, the
/// hover under the pointer does not immediately reopen it.
class StudioAnchoredPanel extends StatefulWidget {
  const StudioAnchoredPanel({
    required this.child,
    required this.panelBuilder,
    this.width = 300,
    this.enabled = true,
    this.pinOpenOnTap = false,
    this.panelIgnoresPointer = false,
    this.semanticsLabel,
    this.semanticsValue,
    this.onHoverChange,
    this.hideDelay = const Duration(milliseconds: 120),
    super.key,
  });

  /// Trigger content; owns its own visuals and hover highlighting.
  final Widget child;

  /// Builds the panel content; called on every rebuild while open.
  final WidgetBuilder panelBuilder;

  /// Preferred panel width; the framework clamps the panel to the measured
  /// safe area on every open and relayout.
  final double width;

  /// Whether hover and taps can open the panel.
  final bool enabled;

  /// Whether tapping the trigger while the panel is open under the pointer
  /// keeps it open instead of toggling it closed.
  final bool pinOpenOnTap;

  /// Whether the panel content ignores business interactions (buttons and
  /// other activators inside the content cannot be triggered). Scrolling
  /// stays available through the scrollbar thumb, so bounded read-only
  /// content remains readable.
  final bool panelIgnoresPointer;

  /// Semantics label for the trigger.
  final String? semanticsLabel;

  /// Semantics value describing the trigger's current state.
  final String? semanticsValue;

  /// Notified when the pointer starts or stops hovering the trigger.
  final ValueChanged<bool>? onHoverChange;

  /// Delay before an unhovered panel closes.
  final Duration hideDelay;

  @override
  State<StudioAnchoredPanel> createState() => _StudioAnchoredPanelState();
}

class _StudioAnchoredPanelState extends State<StudioAnchoredPanel> {
  final MenuController _controller = MenuController();
  Timer? _hideTimer;
  bool _hovering = false;
  bool _pointerDownOnTrigger = false;

  /// Set when a trigger click closed the panel; hover under the pointer must
  /// not reopen it until the pointer actually leaves the trigger once.
  bool _hoverReopenSuppressed = false;

  bool get _isOpen => _controller.isOpen;

  @override
  void dispose() {
    _hideTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MenuAnchor(
      controller: _controller,
      // Pointer opening leaves focus wherever the user was working.
      style: MenuStyle(
        minimumSize: WidgetStatePropertyAll(Size(widget.width, 0)),
        maximumSize: WidgetStatePropertyAll(
          Size(widget.width, double.infinity),
        ),
      ),
      alignmentOffset: const Offset(6, 6),
      onClose: _handleClosed,
      menuChildren: [_buildPanel(context)],
      child: _buildTrigger(context),
    );
  }

  Widget _buildTrigger(BuildContext context) {
    Widget content = Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) {
        _pointerDownOnTrigger = true;
        _handlePointerDown();
      },
      onPointerUp: (_) => _pointerDownOnTrigger = false,
      onPointerCancel: (_) => _pointerDownOnTrigger = false,
      onPointerHover: (_) => _showTransient(),
      child: MouseRegion(
        onEnter: (_) => _handleHover(true),
        onExit: (_) => _handleHover(false),
        child: widget.child,
      ),
    );
    final semanticsLabel = widget.semanticsLabel;
    if (semanticsLabel != null) {
      content = Semantics(
        container: true,
        label: semanticsLabel,
        value: widget.semanticsValue,
        child: content,
      );
    }
    return content;
  }

  Widget _buildPanel(BuildContext context) {
    if (widget.panelIgnoresPointer) {
      // Business interactions inside read-only content are disabled; the
      // framework's own scrollbar thumb keeps the bounded content navigable.
      return IgnorePointer(child: widget.panelBuilder(context));
    }
    return MouseRegion(
      onEnter: (_) => _cancelHide(),
      onExit: (_) => _scheduleHide(),
      child: widget.panelBuilder(context),
    );
  }

  void _handleHover(bool hovering) {
    _hovering = hovering;
    widget.onHoverChange?.call(hovering);
    if (hovering) {
      _showTransient();
    } else {
      // Leaving the trigger re-enables hover shows for the next entry.
      _hoverReopenSuppressed = false;
      _scheduleHide();
    }
  }

  void _handlePointerDown() {
    if (_isOpen && widget.pinOpenOnTap && _hovering) {
      // An open panel under the pointer stays open during a pinned click.
      _cancelHide();
      return;
    }
    _toggle();
  }

  void _toggle() {
    if (_isOpen) {
      _hide();
    } else {
      _show();
    }
  }

  /// Shows the panel transiently without changing the current input focus.
  void _showTransient() {
    _cancelHide();
    if (_hoverReopenSuppressed || _isOpen) {
      return;
    }
    _show();
  }

  void _show() {
    _cancelHide();
    if (!widget.enabled || _isOpen) {
      return;
    }
    _controller.open();
  }

  void _handleClosed() {
    // Framework-initiated closes (outside taps, ancestor scrolls, window
    // resizes) end the session; a stale hide timer must not close a panel
    // that a later interaction reopened.
    _cancelHide();
  }

  void _scheduleHide() {
    _cancelHide();
    _hideTimer = Timer(widget.hideDelay, _hide);
  }

  void _cancelHide() {
    _hideTimer?.cancel();
    _hideTimer = null;
  }

  void _hide() {
    _cancelHide();
    if (!_isOpen) {
      return;
    }
    if (_pointerDownOnTrigger || _hovering) {
      // A click closed the panel while the pointer rests on the trigger;
      // hover events from the same visit must not reopen it until the pointer
      // leaves once.
      _hoverReopenSuppressed = true;
    }
    _controller.close();
  }
}
