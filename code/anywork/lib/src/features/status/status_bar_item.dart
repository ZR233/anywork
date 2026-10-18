import 'package:flutter/material.dart';

import '../../app/theme/studio_tokens.dart';
import '../../shared/studio_hover_detail.dart';

/// 状态栏的一枚只读读数。
///
/// 读数本身不是按钮：点击既不打开也不固定任何面板。较长的内容有两种表达方式——纯文字的
/// [tooltip] 短提示，或承载分区详情的 [detailBuilder]，后者在同一个共享只读悬浮表面里展开，
/// 悬停高亮与详情浮层共用同一块鼠标区域。
class StatusBarItem extends StatefulWidget {
  const StatusBarItem({
    required this.label,
    this.icon,
    this.trailingIcon,
    this.tooltip,
    this.semanticsLabel,
    this.detailBuilder,
    this.detailWidth = 300,
    this.maxWidth = 180,
    super.key,
  }) : assert(
         tooltip == null || detailBuilder == null,
         'A readout either shows a short tooltip or a detail panel, not both.',
       );

  final String label;
  final IconData? icon;
  final IconData? trailingIcon;

  /// 纯文字短提示；与 [detailBuilder] 互斥。
  final String? tooltip;

  /// 可访问性标签；缺省回落到 [label]。
  final String? semanticsLabel;

  /// 悬停详情内容；存在时替换 [tooltip]。
  final WidgetBuilder? detailBuilder;

  final double detailWidth;
  final double maxWidth;

  @override
  State<StatusBarItem> createState() => _StatusBarItemState();
}

class _StatusBarItemState extends State<StatusBarItem> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final foreground = context.colors.onSurfaceVariant;
    final content = AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      height: 26,
      padding: const EdgeInsets.symmetric(horizontal: 7),
      decoration: BoxDecoration(
        color: _hovering
            ? context.colors.surface.withValues(alpha: 0.76)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(StudioRadii.xs),
      ),
      child: Row(
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
      ),
    );
    final hoverable = MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: content,
    );
    final detailBuilder = widget.detailBuilder;
    final Widget readout = detailBuilder == null
        ? hoverable
        : StudioHoverDetail(
            maxWidth: widget.detailWidth,
            semanticsLabel: widget.semanticsLabel ?? widget.label,
            detailBuilder: detailBuilder,
            child: hoverable,
          );
    final chip = Padding(
      padding: const EdgeInsets.only(right: 2),
      child: readout,
    );
    final tooltip = widget.tooltip;
    if (tooltip == null || tooltip.isEmpty) {
      return chip;
    }
    return Tooltip(message: tooltip, child: chip);
  }
}
