import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Hover readouts use Tooltip; activated details use MenuAnchor. Each component
/// keeps its default input, dismissal and focus behavior. This wrapper only
/// supplies content, semantic labels and the trigger's shared focus node.
class StudioAnchoredPanel extends StatefulWidget {
  const StudioAnchoredPanel({
    required this.child,
    required this.panelBuilder,
    this.width = 300,
    this.enabled = true,
    this.panelIgnoresPointer = false,
    this.semanticsLabel,
    this.semanticsValue,
    super.key,
  });

  final Widget child;
  final WidgetBuilder panelBuilder;
  final double width;
  final bool enabled;
  final bool panelIgnoresPointer;
  final String? semanticsLabel;
  final String? semanticsValue;

  @override
  State<StudioAnchoredPanel> createState() => _StudioAnchoredPanelState();
}

class _StudioAnchoredPanelState extends State<StudioAnchoredPanel> {
  final MenuController _controller = MenuController();
  final FocusNode _triggerFocus = FocusNode(
    debugLabel: 'studio-details-trigger',
  );

  @override
  void dispose() {
    _triggerFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MenuAnchor(
      controller: _controller,
      childFocusNode: _triggerFocus,
      style: MenuStyle(
        minimumSize: WidgetStatePropertyAll(Size(widget.width, 0)),
      ),
      menuChildren: [
        if (widget.panelIgnoresPointer)
          IgnorePointer(child: widget.panelBuilder(context))
        else
          widget.panelBuilder(context),
      ],
      builder: (context, controller, child) => Semantics(
        label: widget.semanticsLabel,
        value: widget.semanticsValue,
        child: TooltipVisibility(
          visible: widget.enabled && !controller.isOpen,
          child: Tooltip(
            // A read-only hover preview never opens a menu or moves focus.
            // Click/keyboard activation uses the normal menu below.
            richMessage: WidgetSpan(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: math.max(
                    0,
                    math.min(
                      widget.width,
                      MediaQuery.sizeOf(context).width - 48,
                    ),
                  ),
                  maxHeight: MediaQuery.sizeOf(context).height * 0.6,
                ),
                child: SingleChildScrollView(
                  child: widget.panelBuilder(context),
                ),
              ),
            ),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(4),
            ),
            ignorePointer: true,
            excludeFromSemantics: true,
            child: TextButton(
              focusNode: _triggerFocus,
              onPressed: widget.enabled
                  ? () {
                      if (controller.isOpen) {
                        controller.close();
                      } else {
                        controller.open();
                      }
                    }
                  : null,
              style: TextButton.styleFrom(
                padding: EdgeInsets.zero,
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(6),
                ),
                side: BorderSide.none,
              ),
              child: widget.child,
            ),
          ),
        ),
      ),
    );
  }
}
