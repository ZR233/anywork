import 'package:flutter/material.dart';

import '../../app/theme/studio_tokens.dart';
import '../../shared/studio_anchored_panel.dart';

class StatusBarItem extends StatefulWidget {
  const StatusBarItem({
    required this.label,
    this.icon,
    this.trailingIcon,
    this.tooltip,
    this.semanticsLabel,
    this.detailBuilder,
    this.detailWidth = 300,
    this.enabled = true,
    this.enableHover = true,
    this.interactive = false,
    this.maxWidth = 180,
    super.key,
  });

  final String label;
  final IconData? icon;
  final IconData? trailingIcon;
  final String? tooltip;
  final String? semanticsLabel;
  final WidgetBuilder? detailBuilder;
  final double detailWidth;
  final bool enabled;
  final bool enableHover;
  final bool interactive;
  final double maxWidth;

  @override
  State<StatusBarItem> createState() => _StatusBarItemState();
}

class _StatusBarItemState extends State<StatusBarItem> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final foreground = widget.enabled
        ? context.colors.onSurfaceVariant
        : context.colors.onSurfaceVariant;
    final row = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.icon != null) ...[
          Icon(
            widget.icon,
            size: 13,
            color: foreground.withValues(alpha: 0.76),
          ),
          const SizedBox(width: 7),
        ],
        ConstrainedBox(
          constraints: BoxConstraints(maxWidth: widget.maxWidth),
          child: Text(
            widget.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: context.text.labelSmall?.copyWith(
              color: foreground,
              height: 1,
            ),
          ),
        ),
        if (widget.trailingIcon != null) ...[
          const SizedBox(width: 3),
          Icon(
            widget.trailingIcon,
            size: 14,
            color: foreground.withValues(alpha: 0.56),
          ),
        ],
      ],
    );
    final highlighted = _hovering && widget.enabled;
    final content = AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      height: 26,
      padding: const EdgeInsets.symmetric(horizontal: 7),
      decoration: BoxDecoration(
        color: highlighted
            ? context.colors.surface.withValues(alpha: 0.76)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(StudioRadii.xs),
      ),
      child: row,
    );
    final hoverable = widget.enableHover
        ? MouseRegion(
            onEnter: (_) => setState(() => _hovering = true),
            onExit: (_) => setState(() => _hovering = false),
            child: content,
          )
        : content;
    final detailBuilder = widget.detailBuilder;
    final Widget interactive;
    if (detailBuilder != null) {
      // 详情使用官方 Tooltip/MenuAnchor；本组件只跟踪悬停高亮。
      interactive = StudioAnchoredPanel(
        width: widget.detailWidth,
        enabled: widget.enabled,
        panelIgnoresPointer: !widget.interactive,
        semanticsLabel: widget.interactive
            ? (widget.semanticsLabel ?? widget.label)
            : null,
        semanticsValue: widget.label,
        panelBuilder: detailBuilder,
        child: hoverable,
      );
    } else {
      interactive = hoverable;
    }
    final chip = Padding(
      padding: const EdgeInsets.only(right: 2),
      child: interactive,
    );
    final tooltip = widget.tooltip;
    if (tooltip == null || tooltip.isEmpty) {
      return chip;
    }
    return Tooltip(message: tooltip, child: chip);
  }
}
