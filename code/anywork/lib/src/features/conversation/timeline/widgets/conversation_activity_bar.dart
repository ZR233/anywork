import 'dart:async';
import 'dart:math' as math;

import 'package:anywork_client/studio_client.dart';
import 'package:flutter/material.dart';

import '../../../../app/theme/studio_tokens.dart';
import '../../../../l10n/studio_l10n.dart';
import 'reasoning_summary.dart';
import 'timeline_activity_row.dart';
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
        padding: EdgeInsets.zero,
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
                  padding: const EdgeInsets.fromLTRB(11, 0, 11, 8),
                  child: TimelineActivityRail(
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
    final summaryMd = _view.thinkingSummary?.trim();
    final showSummary = !isExpanded && !_isResponding;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 2),
      child: TimelineActivityRow(
        label: phaseLabel,
        emphasized: true,
        icon: _view.kind.icon,
        isIssue: _view.kind.isIssue,
        active: _view.waits || _isResponding,
        expanded: isExpanded,
        expandable: expandable,
        meta: _trailingMetaText(),
        metaKey: const ValueKey('conversation-activity-trailing-meta'),
        summary: showSummary ? _headerDetail() : null,
        summaryWidget:
            showSummary &&
                summaryMd != null &&
                summaryMd.isNotEmpty &&
                _view.wait == null &&
                !_isCompacting
            ? _InlineSummaryMarkdown(
                id: 'sticky-summary-${_view.identity}',
                markdown: summaryMd,
                color: scheme.onSurfaceVariant,
                fontWeight: FontWeight.w400,
              )
            : null,
      ),
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
    final maxHeight = _effectiveMaxExpandedHeight(context);
    return ConstrainedBox(
      key: const ValueKey('conversation-activity-details'),
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(11, 0, 11, 8),
        child: TimelineActivityRail(
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
    );
  }

  int? _elapsedSeconds(int? startedAt) {
    if (startedAt == null) return null;
    final elapsed = DateTime.now().millisecondsSinceEpoch ~/ 1000 - startedAt;
    return elapsed < 0 ? 0 : elapsed;
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
