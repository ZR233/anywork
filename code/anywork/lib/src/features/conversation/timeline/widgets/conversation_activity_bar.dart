import 'dart:async';
import 'dart:math' as math;

import 'package:anywork_client/studio_client.dart';
import 'package:flutter/material.dart';

import '../../../../app/theme/studio_tokens.dart';
import '../../../../l10n/studio_l10n.dart';
import 'reasoning_summary.dart';
import 'timeline_markdown.dart';

/// 会话输入框上方的实时状态栏。
///
/// [view] 提供标题、阶段与耗时；[content] 是唯一生产正文子树和详情能力入口。
/// 展开、滚动、计时与旋转均由组件自身管理，不从外层接收 UI 控制状态。
class ConversationActivityBar extends StatefulWidget {
  const ConversationActivityBar({
    required this.view,
    this.content,
    this.onExpandedChanged,
    this.maxExpandedHeight = 220,
    this.maxResponseHeight = 180,
    super.key,
  });

  final ConversationActivityView view;
  final Widget? content;

  /// 只通知 Connector 当前真实读取 demand；不用于反向控制组件展开状态。
  final ValueChanged<bool>? onExpandedChanged;
  final double maxExpandedHeight;
  final double maxResponseHeight;

  @override
  State<ConversationActivityBar> createState() =>
      _ConversationActivityBarState();
}

class _ConversationActivityBarState extends State<ConversationActivityBar> {
  final ScrollController _expandedScrollController = ScrollController();
  final ScrollController _responseScrollController = ScrollController();
  Timer? _ticker;
  bool _expanded = false;

  ConversationActivityView get _view => widget.view;

  bool get _isResponding => _view.kind == ConversationActivityKind.responding;

  bool get _isCompacting => _view.kind == ConversationActivityKind.compacting;

  bool get _isExpandable =>
      !_isResponding && !_isCompacting && widget.content != null;

  @override
  void initState() {
    super.initState();
    _syncTicker();
  }

  @override
  void didUpdateWidget(covariant ConversationActivityBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.view.identity != _view.identity ||
        (_expanded && !_isExpandable)) {
      _setExpanded(false);
    }
    _syncTicker();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    if (_expanded) widget.onExpandedChanged?.call(false);
    _expandedScrollController.dispose();
    _responseScrollController.dispose();
    super.dispose();
  }

  double _effectiveMaxExpandedHeight(BuildContext context) {
    final windowHeight = MediaQuery.sizeOf(context).height;
    if (!windowHeight.isFinite || windowHeight <= 0) {
      return widget.maxExpandedHeight;
    }
    return math.min(widget.maxExpandedHeight, windowHeight * 0.45);
  }

  void _syncTicker() {
    final needsTick = _view.activeTools.any((tool) => tool.startedAt != null);
    if (needsTick) {
      _ticker ??= Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    } else {
      _ticker?.cancel();
      _ticker = null;
    }
  }

  void _setExpanded(bool next) {
    if (_expanded == next) return;
    setState(() => _expanded = next);
    widget.onExpandedChanged?.call(next);
  }

  void _toggleExpanded() {
    if (_isExpandable) _setExpanded(!_expanded);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isIssue = _view.kind.isIssue;
    final surfaceColor = isIssue
        ? scheme.errorContainer.withValues(alpha: 0.22)
        : scheme.surfaceContainerLow.withValues(alpha: 0.72);

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 7, 12, 6),
      child: Align(
        alignment: Alignment.center,
        heightFactor: 1,
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: StudioLayout.conversationWidth,
          ),
          child: Material(
            color: surfaceColor,
            clipBehavior: Clip.antiAlias,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(
                color: scheme.outlineVariant.withValues(alpha: 0.72),
              ),
            ),
            child: _isResponding
                ? _buildRespondingSurface(context)
                : _isCompacting
                ? _buildCompactSurface(context)
                : _buildActivitySurface(context),
          ),
        ),
      ),
    );
  }

  Widget _buildRespondingSurface(BuildContext context) {
    final phaseLabel = context.conversationActivityLabel(_view);
    final content = widget.content;
    return Semantics(
      container: true,
      liveRegion: true,
      label: phaseLabel,
      child: Padding(
        key: const ValueKey('conversation-activity'),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: _buildBoundedSurface(
          header: _buildHeaderRow(
            context,
            phaseLabel: phaseLabel,
            expandable: false,
            isExpanded: false,
          ),
          body: content == null
              ? null
              : Padding(
                  padding: const EdgeInsets.only(top: 5),
                  child: ConstrainedBox(
                    key: const ValueKey(
                      'conversation-activity-response-stream',
                    ),
                    constraints: BoxConstraints(
                      maxHeight: widget.maxResponseHeight,
                    ),
                    child: Scrollbar(
                      controller: _responseScrollController,
                      child: SingleChildScrollView(
                        controller: _responseScrollController,
                        primary: false,
                        child: SelectionArea(child: content),
                      ),
                    ),
                  ),
                ),
        ),
      ),
    );
  }

  Widget _buildCompactSurface(BuildContext context) {
    final phaseLabel = context.conversationActivityLabel(_view);
    return Semantics(
      container: true,
      liveRegion: true,
      label: phaseLabel,
      child: Material(
        key: const ValueKey('conversation-activity'),
        type: MaterialType.transparency,
        child: _buildHeaderRow(
          context,
          phaseLabel: phaseLabel,
          expandable: false,
          isExpanded: false,
        ),
      ),
    );
  }

  Widget _buildActivitySurface(BuildContext context) => _buildBoundedSurface(
    header: _buildTopHeaderRow(context),
    body: _expanded && _isExpandable ? _buildExpandedArea(context) : null,
  );

  Widget _buildBoundedSurface({required Widget header, Widget? body}) =>
      LayoutBuilder(
        builder: (context, constraints) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // The composer can consume nearly all footer height during layout.
            // Bound the header too; a non-flex child would otherwise receive
            // infinite height from Column and overflow its real allocation.
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: constraints.maxHeight),
              child: header,
            ),
            if (body != null) Flexible(fit: FlexFit.loose, child: body),
          ],
        ),
      );

  Widget _buildTopHeaderRow(BuildContext context) {
    final phaseLabel = context.conversationActivityLabel(_view);
    final row = _buildHeaderRow(
      context,
      phaseLabel: phaseLabel,
      expandable: _isExpandable,
      isExpanded: _expanded,
    );
    return Semantics(
      container: true,
      liveRegion: true,
      button: _isExpandable,
      expanded: _isExpandable ? _expanded : null,
      label: phaseLabel,
      child: Material(
        key: const ValueKey('conversation-activity'),
        type: MaterialType.transparency,
        child: _isExpandable
            ? InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: _toggleExpanded,
                child: row,
              )
            : row,
      ),
    );
  }

  Widget _buildHeaderRow(
    BuildContext context, {
    required String phaseLabel,
    required bool expandable,
    required bool isExpanded,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final isIssue = _view.kind.isIssue;
    final tone = isIssue ? scheme.error : scheme.onSurface;
    final muted = isIssue ? scheme.error : scheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6.5),
      child: Row(
        children: [
          _ActivityLeading(
            spinning: _view.waits || _isResponding,
            icon: _view.kind.icon,
            color: isIssue ? scheme.error : muted,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _buildHeaderContent(
              context,
              phaseLabel: phaseLabel,
              tone: tone,
              muted: muted,
            ),
          ),
          if (_trailingMetaText() case final trailingMeta?) ...[
            const SizedBox(width: 8),
            Text(
              trailingMeta,
              key: const ValueKey('conversation-activity-trailing-meta'),
              style: context.text.labelSmall?.copyWith(
                fontFamily: studioCodeFontFamily,
                fontSize: 11,
                letterSpacing: 0.2,
                fontFeatures: const [FontFeature.tabularFigures()],
                color: muted.withValues(alpha: 0.78),
                height: 1.2,
              ),
            ),
          ],
          if (expandable) ...[
            const SizedBox(width: 4),
            Icon(
              isExpanded
                  ? Icons.keyboard_arrow_up_rounded
                  : Icons.keyboard_arrow_down_rounded,
              size: 16,
              color: muted,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildHeaderContent(
    BuildContext context, {
    required String phaseLabel,
    required Color tone,
    required Color muted,
  }) {
    final summaryMd = _view.thinkingSummary?.trim();
    if (summaryMd != null &&
        summaryMd.isNotEmpty &&
        _view.wait == null &&
        !_isResponding &&
        !_isCompacting) {
      return _InlineSummaryMarkdown(
        id: 'sticky-summary-${_view.identity}',
        markdown: summaryMd,
        color: tone,
        fontWeight: FontWeight.w600,
      );
    }

    final detailText = _headerDetail();
    return Row(
      children: [
        Flexible(
          flex: detailText == null ? 1 : 0,
          child: Text(
            phaseLabel,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: context.text.bodySmall?.copyWith(
              color: tone,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.15,
              height: 1.25,
            ),
          ),
        ),
        if (detailText != null && detailText.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Text(
              '·',
              style: context.text.bodySmall?.copyWith(
                color: muted,
                height: 1.25,
              ),
            ),
          ),
          Expanded(
            child: Text(
              detailText,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.text.bodySmall?.copyWith(
                fontFamily: _view.kind == ConversationActivityKind.runningTool
                    ? studioCodeFontFamily
                    : null,
                color: muted,
                letterSpacing: 0.1,
                height: 1.25,
              ),
            ),
          ),
        ],
      ],
    );
  }

  String? _headerDetail() {
    final error = _view.errorMessage?.trim();
    if (error != null && error.isNotEmpty) return error;
    if (_view.kind == ConversationActivityKind.runningTool &&
        _view.activeTools.isNotEmpty &&
        _view.wait == null) {
      return _view.activeTools.last.singleLineLabel;
    }
    final summary = _view.summary?.trim();
    return summary == null || summary.isEmpty ? null : summary;
  }

  String? _trailingMetaText() {
    final toolCount = math.max(_view.activeToolCount, _view.activeTools.length);
    if (toolCount > 1) return '×$toolCount';
    if (_view.kind == ConversationActivityKind.runningTool &&
        _view.activeTools.isNotEmpty) {
      final elapsed = _elapsedSeconds(_view.activeTools.last.startedAt);
      if (elapsed != null) return '${elapsed}s';
    }
    final thinkingSeconds = _view.thinkingSeconds;
    if (_view.kind == ConversationActivityKind.thinking &&
        thinkingSeconds != null &&
        thinkingSeconds > 0) {
      return '${thinkingSeconds}s';
    }
    return null;
  }

  Widget _buildExpandedArea(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final maxHeight = _effectiveMaxExpandedHeight(context);
    return ConstrainedBox(
      key: const ValueKey('conversation-activity-details'),
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(15, 0, 10, 8),
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(
                color: scheme.outlineVariant.withValues(alpha: 0.58),
              ),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.only(left: 11),
            child: Scrollbar(
              controller: _expandedScrollController,
              child: SingleChildScrollView(
                controller: _expandedScrollController,
                primary: false,
                child: SelectionArea(child: widget.content!),
              ),
            ),
          ),
        ),
      ),
    );
  }

  int? _elapsedSeconds(int? startedAt) {
    if (startedAt == null) return null;
    final elapsed = DateTime.now().millisecondsSinceEpoch ~/ 1000 - startedAt;
    return elapsed < 0 ? 0 : elapsed;
  }
}

class _ActivityLeading extends StatefulWidget {
  const _ActivityLeading({
    required this.spinning,
    required this.icon,
    required this.color,
  });

  final bool spinning;
  final IconData icon;
  final Color color;

  @override
  State<_ActivityLeading> createState() => _ActivityLeadingState();
}

class _ActivityLeadingState extends State<_ActivityLeading>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(covariant _ActivityLeading oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  bool get _reducedMotion =>
      MediaQuery.disableAnimationsOf(context) ||
      !TickerMode.valuesOf(context).enabled;

  void _sync() {
    if (widget.spinning && !_reducedMotion) {
      if (!_controller.isAnimating) _controller.repeat();
    } else {
      _controller.stop();
      _controller.value = 0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final icon = Icon(
      widget.spinning ? Icons.refresh : widget.icon,
      key: const ValueKey('conversation-activity-leading'),
      size: 15,
      color: widget.color,
    );
    if (!widget.spinning || _reducedMotion) {
      return SizedBox(width: 14, height: 14, child: Center(child: icon));
    }
    return SizedBox(
      width: 14,
      height: 14,
      child: RotationTransition(
        key: const ValueKey('conversation-activity-leading-spin'),
        turns: _controller,
        child: icon,
      ),
    );
  }
}

class _InlineSummaryMarkdown extends StatelessWidget {
  const _InlineSummaryMarkdown({
    required this.id,
    required this.markdown,
    required this.color,
    required this.fontWeight,
  });

  final String id;
  final String markdown;
  final Color color;
  final FontWeight fontWeight;

  @override
  Widget build(BuildContext context) {
    final inlineText =
        inlineReasoningSummaryMarkdown(markdown) ?? markdown.trim();
    return TimelineMarkdown(
      id: 'live-inline-md-$id',
      text: inlineText,
      style: context.text.bodySmall?.copyWith(
        color: color,
        fontWeight: fontWeight,
        letterSpacing: 0.1,
        height: 1.25,
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      onLink: (_) {},
      isSafeLink: (_) => false,
      imageBuilder: (_, url) => Text(url),
    );
  }
}
