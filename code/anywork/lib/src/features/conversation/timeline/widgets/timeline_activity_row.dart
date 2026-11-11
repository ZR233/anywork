import 'package:material_ui/material_ui.dart';

import '../../../../app/theme/studio_tokens.dart';
import 'timeline_resting_cat.dart';
import 'timeline_writing_indicator.dart';

enum TimelineActivityIndicatorStyle { restingCat, writing }

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
    this.indicatorStyle = TimelineActivityIndicatorStyle.restingCat,
    this.expanded = false,
    this.expandable = true,
    this.tooltip,
    this.summary,
    this.summaryWidget,
    this.meta,
    this.metaKey,
    this.emphasized = false,
    this.header = false,
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

  /// 实时状态栏顶行固定几何常量：保证跨工况切换时 Logo 槽与文案起点零偏移、行高零抖动。
  static const double headerLogoSlotSize = 32;
  static const double headerGap = 10;
  static const double headerContentIndent = headerLogoSlotSize + headerGap;
  static const double headerMinHeight = 34;
  static const double headerFontSize = 15;
  static const double headerMetaFontSize = 12.5;
  static const double headerChevronSize = 19;
  static const double headerWritingSize = 23;
  static const double headerStaticIconSize = 20;
  static const StrutStyle headerStrutStyle = StrutStyle(
    fontSize: headerFontSize,
    height: 1.36,
    forceStrutHeight: true,
  );

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
  final TimelineActivityIndicatorStyle indicatorStyle;

  final bool expanded;

  /// 是否存在可展开内容；没有内容时不显示箭头。
  final bool expandable;

  final String? tooltip;
  final String? summary;
  final Widget? summaryWidget;
  final String? meta;
  final Key? metaKey;
  final bool emphasized;

  /// 状态与组标题保持全文；摘要可省略，统计在不足时换行。
  final bool header;

  @override
  Widget build(BuildContext context) {
    final color = context.colors.onSurfaceVariant;
    final textStyle = context.text.bodySmall!.copyWith(
      color: header
          ? (active
                ? (emphasized
                      ? context.colors.onSurface
                      : context.colors.onSurface.withValues(alpha: .92))
                : color)
          : color,
      fontSize: header ? headerFontSize : null,
      fontWeight: header || emphasized ? FontWeight.w500 : FontWeight.w400,
      height: header ? 1.36 : 1.5,
    );
    final metaStyle = context.text.labelSmall!.copyWith(
      color: color.withValues(alpha: header ? .85 : .78),
      fontSize: header ? headerMetaFontSize : 10.5,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final showLeading = leading != null || icon != null || isIssue || active;
    final leadingWidth = header ? headerLogoSlotSize : iconColumnWidth;
    final rowGap = header ? headerGap : gap;
    final labelView =
        labelWidget ??
        Text(
          label,
          key: labelKey,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          softWrap: false,
          strutStyle: header ? headerStrutStyle : null,
          style: textStyle,
        );
    final detail =
        summaryWidget ??
        (summary == null
            ? null
            : Text(
                summary!,
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.ellipsis,
                strutStyle: header ? headerStrutStyle : null,
                style: textStyle.copyWith(
                  color: color,
                  fontSize: header ? 13 : 11.5,
                  fontWeight: FontWeight.w400,
                ),
              ));
    final mark = Icon(
      expanded
          ? Icons.keyboard_arrow_down_rounded
          : Icons.chevron_right_rounded,
      size: header ? headerChevronSize : 15,
      color: color.withValues(alpha: header ? .8 : .72),
    );
    final symbol = showLeading
        ? SizedBox(
            width: leadingWidth,
            height: header ? headerLogoSlotSize : null,
            child: Center(
              heightFactor: 1,
              child:
                  leading ??
                  TimelineActivityIndicator(
                    icon: isIssue ? Icons.error_outline : icon,
                    active: active && !isIssue,
                    style: indicatorStyle,
                    catSize: header ? headerLogoSlotSize : iconColumnWidth,
                    writingSize: header ? headerWritingSize : iconSize,
                    staticIconSize: header ? headerStaticIconSize : iconSize,
                    color:
                        iconColor ??
                        (isIssue
                            ? context.colors.error
                            : active
                            ? context.statusColors.activeIndicator
                            : color.withValues(alpha: .78)),
                  ),
            ),
          )
        : null;
    Widget row = SelectionContainer.disabled(
      child: LayoutBuilder(
        builder: (context, constraints) {
          double measure(String value, TextStyle style) {
            final painter = TextPainter(
              text: TextSpan(text: value, style: style),
              textDirection: Directionality.of(context),
              textScaler: MediaQuery.textScalerOf(context),
            )..layout();
            final width = painter.width;
            painter.dispose();
            return width;
          }

          final stacked =
              !header &&
              meta != null &&
              measure(label, textStyle) +
                      measure(meta!, metaStyle) +
                      (showLeading ? leadingWidth + rowGap : 0) +
                      (expandable ? 19 : 0) +
                      16 >
                  constraints.maxWidth;
          final content = Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              if (symbol != null) ...[symbol, SizedBox(width: rowGap)],
              Flexible(child: labelView),
              if (!stacked && detail != null) ...[
                const SizedBox(width: 8),
                Flexible(child: detail),
              ],
              if (!header && expandable) ...[const SizedBox(width: 4), mark],
            ],
          );
          final title = (!stacked && meta != null) || (header && expandable)
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(child: content),
                    if (!stacked && meta != null) ...[
                      const SizedBox(width: 8),
                      Text(
                        meta!,
                        key: metaKey,
                        maxLines: 1,
                        softWrap: false,
                        style: metaStyle,
                      ),
                    ],
                    if (header && expandable) ...[
                      const SizedBox(width: 4),
                      mark,
                    ],
                  ],
                )
              : content;
          return ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: header ? headerMinHeight : 28,
            ),
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: header ? 2 : 4),
              child: stacked
                  ? Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        title,
                        Padding(
                          padding: EdgeInsetsDirectional.only(
                            start: showLeading ? leadingWidth + rowGap : 0,
                            top: 2,
                          ),
                          child: Wrap(
                            spacing: 8,
                            runSpacing: 3,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              ?detail,
                              Text(meta!, key: metaKey, style: metaStyle),
                            ],
                          ),
                        ),
                      ],
                    )
                  : Align(
                      alignment: AlignmentDirectional.centerStart,
                      heightFactor: 1,
                      child: title,
                    ),
            ),
          );
        },
      ),
    );
    if (tooltip != null) row = Tooltip(message: tooltip!, child: row);
    return ColoredBox(color: Colors.transparent, child: row);
  }
}

/// 实时状态栏共享的趴卧猫摆尾时钟宿主：保持同一次实时展示跨状态切换时尾巴相位连续不归零，
/// 并在无活跃订阅或禁用动画时立即停表，避免空闲占用与测试 `pumpAndSettle` 超时。
class LiveStatusMotionHost extends StatefulWidget {
  const LiveStatusMotionHost({required this.child, super.key});
  final Widget child;

  static LiveStatusMotionController? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<_LiveStatusMotionScope>()
      ?.controller;

  @override
  State<LiveStatusMotionHost> createState() => _LiveStatusMotionHostState();
}

class LiveStatusMotionController {
  LiveStatusMotionController(this._controller, this._onActiveChanged);
  final AnimationController _controller;
  final VoidCallback _onActiveChanged;
  int _subscribers = 0;

  Animation<double> get progress => _controller;
  bool get hasSubscribers => _subscribers > 0;

  void attach() {
    _subscribers++;
    _onActiveChanged();
  }

  void detach() {
    if (_subscribers > 0) {
      _subscribers--;
      _onActiveChanged();
    }
  }
}

class _LiveStatusMotionHostState extends State<LiveStatusMotionHost>
    with SingleTickerProviderStateMixin {
  late final AnimationController _motion = AnimationController(
    vsync: this,
    duration: TimelineRestingCat.duration,
  )..addStatusListener(_onStatus);
  late final LiveStatusMotionController _shared = LiveStatusMotionController(
    _motion,
    _sync,
  );
  bool _canAnimate = false;

  void _onStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed &&
        _canAnimate &&
        _shared.hasSubscribers) {
      _motion.forward(from: 0);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _canAnimate =
        !MediaQuery.disableAnimationsOf(context) &&
        TickerMode.valuesOf(context).enabled;
    _sync();
  }

  void _sync() {
    if (!mounted) return;
    if (_canAnimate && _shared.hasSubscribers) {
      if (!_motion.isAnimating) {
        _motion.forward(from: _motion.value >= 1.0 ? 0.0 : _motion.value);
      }
    } else if (_motion.isAnimating) {
      _motion.stop();
    }
  }

  @override
  void dispose() {
    _motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      _LiveStatusMotionScope(controller: _shared, child: widget.child);
}

class _LiveStatusMotionScope extends InheritedWidget {
  const _LiveStatusMotionScope({
    required this.controller,
    required super.child,
  });
  final LiveStatusMotionController controller;

  @override
  bool updateShouldNotify(_LiveStatusMotionScope oldWidget) =>
      !identical(controller, oldWidget.controller);
}

/// Shared running semantics, using Flutter's standard animation lifecycle.
class TimelineActivityIndicator extends StatefulWidget {
  const TimelineActivityIndicator({
    required this.icon,
    required this.color,
    this.active = false,
    this.style = TimelineActivityIndicatorStyle.restingCat,
    this.catSize = TimelineActivityRow.iconColumnWidth,
    this.writingSize = TimelineActivityRow.iconSize,
    this.staticIconSize = TimelineActivityRow.iconSize,
    super.key,
  });

  final IconData? icon;
  final Color color;
  final bool active;
  final TimelineActivityIndicatorStyle style;
  final double catSize;
  final double writingSize;
  final double staticIconSize;

  @override
  State<TimelineActivityIndicator> createState() =>
      _TimelineActivityIndicatorState();
}

class _TimelineActivityIndicatorState extends State<TimelineActivityIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _motion = AnimationController(
    vsync: this,
    duration: _duration,
  );
  LiveStatusMotionController? _sharedCat;
  bool _attachedToShared = false;

  Duration get _duration =>
      widget.style == TimelineActivityIndicatorStyle.writing
      ? const Duration(milliseconds: 900)
      : TimelineRestingCat.duration;

  static final _writingStroke = TweenSequence<Offset>([
    for (final (from, to) in const [
      (Offset(-.08, .06), Offset(.08, -.06)),
      (Offset(.08, -.06), Offset(-.04, .06)),
      (Offset(-.04, .06), Offset(.12, -.04)),
      (Offset(.12, -.04), Offset(-.08, .06)),
    ])
      TweenSequenceItem(
        tween: Tween(
          begin: from,
          end: to,
        ).chain(CurveTween(curve: Curves.easeInOut)),
        weight: 1,
      ),
  ]);

  bool get _usesSharedCat =>
      _sharedCat != null &&
      widget.active &&
      widget.style == TimelineActivityIndicatorStyle.restingCat;

  bool get _animate =>
      widget.active &&
      !MediaQuery.disableAnimationsOf(context) &&
      TickerMode.valuesOf(context).enabled;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final nextShared = LiveStatusMotionHost.maybeOf(context);
    if (!identical(_sharedCat, nextShared)) {
      _detachShared();
      _sharedCat = nextShared;
    }
    _sync();
  }

  @override
  void didUpdateWidget(covariant TimelineActivityIndicator oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.style != widget.style) {
      _motion.stop();
      _motion.value = 0;
      _motion.duration = _duration;
    }
    _sync();
  }

  void _detachShared() {
    if (_attachedToShared) {
      _attachedToShared = false;
      _sharedCat?.detach();
    }
  }

  void _sync() {
    if (_usesSharedCat) {
      if (_motion.isAnimating) _motion.stop();
      if (_animate) {
        if (!_attachedToShared) {
          _attachedToShared = true;
          _sharedCat!.attach();
        }
      } else {
        _detachShared();
      }
      return;
    }
    _detachShared();
    if (_animate) {
      if (!_motion.isAnimating) _motion.repeat();
    } else {
      _motion.stop();
      _motion.value = 0;
    }
  }

  @override
  void dispose() {
    _detachShared();
    _motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.active) {
      if (widget.style == TimelineActivityIndicatorStyle.writing) {
        return TimelineWritingIndicator(
          position: _writingStroke.animate(_motion),
          size: widget.writingSize,
          color: widget.color,
        );
      }
      return TimelineRestingCat(
        progress: _usesSharedCat ? _sharedCat!.progress : _motion,
        color: widget.color,
        size: widget.catSize,
      );
    }
    return Icon(widget.icon, size: widget.staticIconSize, color: widget.color);
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
  const TimelineActivityRail({
    required this.child,
    this.inset = 10,
    this.contentInset = 17,
    super.key,
  });

  final double inset;
  final double contentInset;

  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsetsDirectional.only(start: inset),
    child: DecoratedBox(
      decoration: BoxDecoration(
        border: BorderDirectional(
          start: BorderSide(
            color: context.colors.outlineVariant.withValues(alpha: .58),
          ),
        ),
      ),
      child: Padding(
        padding: EdgeInsetsDirectional.only(start: contentInset),
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
