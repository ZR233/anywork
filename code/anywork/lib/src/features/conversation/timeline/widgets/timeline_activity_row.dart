import 'package:flutter/material.dart';

import '../../../../app/theme/studio_tokens.dart';

/// 活动行共用的轻量基座：固定图标列、单行次级文案、紧邻文案的展开箭头。
///
/// Timeline 的组摘要、思考、工具、搜索与等候成员统一使用这一行，因此它们的图标与
/// 文案起点分别对齐，展开后也不出现卡片、多行参数摘要或额外标题缩进
/// （design/19 §19.9）。活动组成员在折叠态只渲染这一行；紧随成员的正文读取入口
/// （每个被截断字段一行）与原文不可得说明同样使用这一行，不再另起说明句或按钮组。
/// 类目语义由调用方给出的图标表达；失败只用错误图标与状态文案
/// 表达，不把整行染成错误色。文案保持为普通 [Text]：摘要会持续追加，不能每次
/// 变化都触发以文本为 key 的进出场动画。
class TimelineActivityRow extends StatelessWidget {
  const TimelineActivityRow({
    required this.label,
    this.icon,
    this.labelWidget,
    this.labelKey,
    this.leading,
    this.iconColor,
    this.isIssue = false,
    this.active = false,
    this.expanded = false,
    this.expandable = true,
    this.tooltip,
    this.summary,
    this.summaryWidget,
    this.meta,
    this.metaKey,
    this.emphasized = false,
    super.key,
  });

  /// 图标列宽度：所有活动行的文字都从这一列之后开始。
  static const double iconColumnWidth = 20;

  /// 图标与文案之间的间距。
  static const double gap = 8;

  /// 展开内容与文案列对齐所需的左内边距。
  static const double contentIndent = iconColumnWidth + gap;

  /// 活动组成员相对组标题的缩进：正好一档图标列宽度。
  static const double groupIndent = iconColumnWidth;

  static const double iconSize = 15;

  /// 类目语义图标；为空且无 [leading] / [isIssue] 时不渲染前导图标列（例如活动组总折叠行）。
  final IconData? icon;

  /// 单行文案；过长在行内省略，完整内容由 [tooltip] 提供。
  final String label;
  final Key? labelKey;

  /// 自定义行内富文本组件（例如思考行的行内 Markdown 概要）；为空时使用 [label]。
  final Widget? labelWidget;

  /// 取代语义图标的前导组件（例如等待脉冲），仍落在同一图标列内。
  final Widget? leading;

  /// 状态色覆盖；缺省使用次级文字色。
  final Color? iconColor;

  /// 该行代表真正失败、拒绝或预算限制：只替换图标，不改变文案颜色。
  /// 取消与中断是正常控制结果，保持中性图标与次级色。
  final bool isIssue;

  /// 该行对应的成员仍在进行中。
  final bool active;

  final bool expanded;

  /// 是否存在可展开内容；没有内容时不显示箭头。
  final bool expandable;

  final String? tooltip;
  final String? summary;
  final Widget? summaryWidget;
  final String? meta;
  final Key? metaKey;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final color = context.colors.onSurfaceVariant;
    final resolvedIconColor =
        iconColor ??
        (isIssue
            ? context.colors.error
            : active
            ? context.statusColors.activeIndicator
            : color.withValues(alpha: .78));
    final showLeading = leading != null || icon != null || isIssue || active;
    Widget row = Align(
      alignment: AlignmentDirectional.centerStart,
      heightFactor: 1,
      child: SelectionContainer.disabled(
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 28),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (showLeading) ...[
                  SizedBox(
                    width: iconColumnWidth,
                    child: Center(
                      heightFactor: 1,
                      child:
                          leading ??
                          TimelineActivityIndicator(
                            icon: isIssue ? Icons.error_outline : icon,
                            active: active && !isIssue,
                            color: resolvedIconColor,
                          ),
                    ),
                  ),
                  const SizedBox(width: gap),
                ],
                Flexible(
                  child:
                      labelWidget ??
                      Text(
                        label,
                        key: labelKey,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        softWrap: false,
                        style: context.text.bodySmall?.copyWith(
                          color: color,
                          fontWeight: emphasized
                              ? FontWeight.w600
                              : FontWeight.w400,
                          height: 1.25,
                        ),
                      ),
                ),
                if (summaryWidget != null || summary != null) ...[
                  const SizedBox(width: 8),
                  Flexible(
                    child:
                        summaryWidget ??
                        Text(
                          summary!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: context.text.bodySmall?.copyWith(
                            color: color,
                            height: 1.25,
                          ),
                        ),
                  ),
                ],
                if (expandable) const SizedBox(width: 4),
                if (expandable)
                  Icon(
                    expanded
                        ? Icons.keyboard_arrow_down_rounded
                        : Icons.chevron_right_rounded,
                    size: 15,
                    color: color.withValues(alpha: 0.72),
                  ),
                if (meta != null) ...[
                  const Spacer(),
                  const SizedBox(width: 8),
                  Text(
                    meta!,
                    key: metaKey,
                    style: context.text.labelSmall?.copyWith(
                      color: color.withValues(alpha: .78),
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
    final tooltip = this.tooltip;
    if (tooltip != null) {
      row = Tooltip(message: tooltip, child: row);
    }
    return row;
  }
}

/// Shared running semantics, using Flutter's standard animation lifecycle.
class TimelineActivityIndicator extends StatefulWidget {
  const TimelineActivityIndicator({
    required this.icon,
    required this.color,
    this.active = false,
    super.key,
  });

  final IconData? icon;
  final Color color;
  final bool active;

  @override
  State<TimelineActivityIndicator> createState() =>
      _TimelineActivityIndicatorState();
}

class _TimelineActivityIndicatorState extends State<TimelineActivityIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _rotation = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );

  bool get _animate =>
      widget.active &&
      !MediaQuery.disableAnimationsOf(context) &&
      TickerMode.valuesOf(context).enabled;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(covariant TimelineActivityIndicator oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  void _sync() {
    if (_animate) {
      if (!_rotation.isAnimating) _rotation.repeat();
    } else {
      _rotation.stop();
      _rotation.value = 0;
    }
  }

  @override
  void dispose() {
    _rotation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final icon = Icon(
      widget.active ? Icons.refresh : widget.icon,
      size: TimelineActivityRow.iconSize,
      color: widget.color,
    );
    return _animate ? RotationTransition(turns: _rotation, child: icon) : icon;
  }
}

/// Domain styling only: ExpansionTile owns expansion, animation and semantics.
class TimelineActivityDisclosure extends StatefulWidget {
  const TimelineActivityDisclosure({
    required this.titleBuilder,
    required this.children,
    this.initiallyExpanded = false,
    this.enabled = true,
    this.onExpansionChanged,
    this.childrenPadding = const EdgeInsetsDirectional.only(bottom: 8),
    super.key,
  });

  final Widget Function(BuildContext context, bool expanded) titleBuilder;
  final List<Widget> children;
  final bool initiallyExpanded;
  final bool enabled;
  final ValueChanged<bool>? onExpansionChanged;
  final EdgeInsetsGeometry childrenPadding;

  @override
  State<TimelineActivityDisclosure> createState() =>
      _TimelineActivityDisclosureState();
}

class _TimelineActivityDisclosureState
    extends State<TimelineActivityDisclosure> {
  late bool _expanded = widget.initiallyExpanded;

  @override
  Widget build(BuildContext context) => TimelineActivityTileTheme(
    child: ExpansionTile(
      initiallyExpanded: widget.initiallyExpanded,
      enabled: widget.enabled,
      maintainState: false,
      onExpansionChanged: (expanded) {
        setState(() => _expanded = expanded);
        widget.onExpansionChanged?.call(expanded);
      },
      showTrailingIcon: false,
      minTileHeight: 28,
      dense: true,
      tilePadding: EdgeInsets.zero,
      childrenPadding: widget.childrenPadding,
      shape: const Border(),
      collapsedShape: const Border(),
      expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
      title: widget.titleBuilder(context, _expanded),
      children: [
        TimelineActivityRail(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: widget.children,
          ),
        ),
      ],
    ),
  );
}

/// A shared reading axis, without content or resource ownership.
class TimelineActivityRail extends StatelessWidget {
  const TimelineActivityRail({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsetsDirectional.only(start: 10),
    child: DecoratedBox(
      decoration: BoxDecoration(
        border: BorderDirectional(
          start: BorderSide(
            color: context.colors.outlineVariant.withValues(alpha: .58),
          ),
        ),
      ),
      child: Padding(
        padding: const EdgeInsetsDirectional.only(start: 17),
        child: child,
      ),
    ),
  );
}

/// 活动行作用域的紧凑 ListTile 主题：只把最小垂直内边距收敛到 0。
///
/// 活动行自带 28px 行高与内容内边距，ListTile 默认的上下最小内边距会把相邻行
/// 步进推到 44px 以上，明显比阅读节奏松。主题只覆盖活动组与活动行子树，不改全局
/// `ThemeData.listTileTheme`、不改其它页面；行高仍由内容自然撑开，缩放或换行时不会被
/// 固定高度裁字。
class TimelineActivityTileTheme extends StatelessWidget {
  const TimelineActivityTileTheme({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ListTileTheme(
      data: ListTileTheme.of(context).copyWith(minVerticalPadding: 0),
      child: child,
    );
  }
}
