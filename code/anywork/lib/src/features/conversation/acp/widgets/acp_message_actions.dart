import 'dart:async';

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../app/theme/studio_tokens.dart';
import '../../../../l10n/studio_l10n.dart';

/// Compact clipboard copy icon button with a 1.8s checkmark confirmation.
class AcpCopyIconButton extends StatefulWidget {
  const AcpCopyIconButton({
    super.key,
    required this.text,
    required this.tooltip,
    this.onCopy,
    this.baseOpacity = 0.5,
  });

  final String text;
  final String tooltip;
  final ValueChanged<String>? onCopy;
  final double baseOpacity;

  @override
  State<AcpCopyIconButton> createState() => _AcpCopyIconButtonState();
}

class _AcpCopyIconButtonState extends State<AcpCopyIconButton> {
  bool _hovered = false;
  bool _copied = false;
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _handleTap() {
    final text = widget.text;
    if (widget.onCopy != null) {
      widget.onCopy!(text);
    } else {
      unawaited(Clipboard.setData(ClipboardData(text: text)));
    }
    _timer?.cancel();
    setState(() => _copied = true);
    _timer = Timer(const Duration(milliseconds: 1800), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = context.colors;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedOpacity(
        opacity: (_hovered || _copied) ? 1.0 : widget.baseOpacity,
        duration: const Duration(milliseconds: 140),
        child: Tooltip(
          message: _copied ? l10n.timelineOutcomeCopied : widget.tooltip,
          child: InkWell(
            onTap: _handleTap,
            borderRadius: const BorderRadius.all(Radius.circular(6)),
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Icon(
                _copied ? Icons.check_rounded : Icons.content_copy_rounded,
                size: 14,
                color: _copied ? colors.primary : colors.onSurfaceVariant,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Automatically folds long user messages (`>= foldThresholdHeight`) to
/// `collapsedMaxHeight` with a soft fade scrim and an expand/collapse toggle,
/// keeping short/medium bubbles completely untouched.
class AcpCollapsibleUserBubble extends StatefulWidget {
  const AcpCollapsibleUserBubble({
    super.key,
    required this.toggleKey,
    required this.bubbleColor,
    required this.child,
    this.collapsedMaxHeight = 180.0,
    this.foldThresholdHeight = 360.0,
  });

  final Key toggleKey;
  final Color bubbleColor;
  final Widget child;
  final double collapsedMaxHeight;
  final double foldThresholdHeight;

  @override
  State<AcpCollapsibleUserBubble> createState() =>
      _AcpCollapsibleUserBubbleState();
}

class _AcpCollapsibleUserBubbleState extends State<AcpCollapsibleUserBubble> {
  bool _tallEnough = false;
  bool _expanded = false;

  void _onChildHeightChanged(double height) {
    final next = height >= widget.foldThresholdHeight;
    if (next == _tallEnough || !mounted) return;
    setState(() => _tallEnough = next);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final collapsed = _tallEnough && !_expanded;
    final measured = _MeasureChildHeight(
      onHeightChanged: _onChildHeightChanged,
      child: widget.child,
    );

    final Widget body;
    if (!collapsed) {
      body = measured;
    } else {
      body = Stack(
        children: [
          ConstrainedBox(
            constraints: BoxConstraints(maxHeight: widget.collapsedMaxHeight),
            child: ClipRect(
              child: SingleChildScrollView(
                primary: false,
                physics: const NeverScrollableScrollPhysics(),
                child: measured,
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: 44,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      widget.bubbleColor.withValues(alpha: 0.0),
                      widget.bubbleColor.withValues(alpha: 0.94),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    }

    if (!_tallEnough) return body;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        body,
        const SizedBox(height: 4),
        TextButton.icon(
          key: widget.toggleKey,
          onPressed: () => setState(() => _expanded = !_expanded),
          style: TextButton.styleFrom(
            visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            minimumSize: const Size(0, 26),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            foregroundColor: context.colors.primary,
          ),
          icon: Icon(
            _expanded
                ? Icons.keyboard_arrow_up_rounded
                : Icons.keyboard_arrow_down_rounded,
            size: 16,
          ),
          label: Text(
            _expanded
                ? l10n.timelineOutcomeShowLess
                : l10n.timelineOutcomeShowMore,
            style: context.text.labelSmall?.copyWith(
              color: context.colors.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

class _MeasureChildHeight extends SingleChildRenderObjectWidget {
  const _MeasureChildHeight({required this.onHeightChanged, super.child});

  final ValueChanged<double> onHeightChanged;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderMeasureChildHeight(onHeightChanged);

  @override
  void updateRenderObject(
    BuildContext context,
    covariant _RenderMeasureChildHeight renderObject,
  ) {
    renderObject.onHeightChanged = onHeightChanged;
  }
}

class _RenderMeasureChildHeight extends RenderProxyBox {
  _RenderMeasureChildHeight(this.onHeightChanged);

  ValueChanged<double> onHeightChanged;
  double? _lastHeight;

  @override
  void performLayout() {
    super.performLayout();
    final currentHeight = child?.size.height ?? 0;
    if (_lastHeight != null && (currentHeight - _lastHeight!).abs() < 0.5) {
      return;
    }
    _lastHeight = currentHeight;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      onHeightChanged(currentHeight);
    });
  }
}
