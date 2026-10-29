import 'dart:async';
import 'dart:math' as math;

import 'package:anywork_client/studio_client.dart';
import 'package:flutter/material.dart';

import '../../../../app/theme/studio_tokens.dart';
import '../../../../l10n/studio_l10n.dart';
import '../../../../shared/studio_code_block.dart';
import 'reasoning_summary.dart';
import 'timeline_markdown.dart';

/// 会话输入框上方的实时状态栏：只渲染 SDK 活动当前态。
///
/// 展开、滚动与工具耗时显示是本地呈现状态；阶段、正文、工具列表不在此归约。
class ConversationActivityBar extends StatefulWidget {
  const ConversationActivityBar({
    required this.view,
    this.onExpand,
    this.onCollapse,
    this.onExpandedChanged,
    this.maxExpandedHeight = 220,
    this.maxResponseHeight = 180,
    super.key,
  });

  final ConversationActivityView view;
  final VoidCallback? onExpand;
  final VoidCallback? onCollapse;
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
  final Set<String> _expandedToolIds = <String>{};
  Timer? _ticker;
  bool _expanded = false;
  bool? _lastReportedExpanded;

  ConversationActivityView get _view => widget.view;

  bool get _isResponding => _view.kind == ConversationActivityKind.responding;

  bool get _isCompacting => _view.kind == ConversationActivityKind.compacting;

  bool get _hasReasoningBody =>
      _view.reasoningParts.any((part) => part.text.isNotEmpty);

  bool get _hasTools =>
      _view.activeTools.isNotEmpty || _view.toolDetails.isNotEmpty;

  bool get _isExpandable {
    if (_isResponding || _isCompacting) return false;
    if (_view.kind == ConversationActivityKind.thinking &&
        !_hasReasoningBody &&
        !_hasTools &&
        _view.details.isEmpty) {
      return false;
    }
    return _view.expandable ||
        _hasReasoningBody ||
        _hasTools ||
        _view.details.isNotEmpty;
  }

  @override
  void initState() {
    super.initState();
    _syncTicker();
  }

  @override
  void didUpdateWidget(covariant ConversationActivityBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.view.identity != _view.identity) {
      _expandedToolIds.clear();
      if (_expanded) {
        _setExpanded(false, notifyCallbacks: true);
      }
    } else if (_expanded && !_isExpandable) {
      _setExpanded(false, notifyCallbacks: true);
    }
    _syncTicker();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    if (_lastReportedExpanded == true) {
      widget.onCollapse?.call();
    }
    widget.onExpandedChanged?.call(false);
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

  void _reportExpandedIfChanged() {
    if (_lastReportedExpanded == _expanded) return;
    _lastReportedExpanded = _expanded;
    widget.onExpandedChanged?.call(_expanded);
  }

  void _setExpanded(bool next, {required bool notifyCallbacks}) {
    if (_expanded == next) {
      _reportExpandedIfChanged();
      return;
    }
    setState(() => _expanded = next);
    if (notifyCallbacks) {
      if (next) {
        widget.onExpand?.call();
      } else {
        widget.onCollapse?.call();
      }
    }
    _reportExpandedIfChanged();
  }

  void _toggleTopExpanded() {
    if (!_isExpandable) return;
    _setExpanded(!_expanded, notifyCallbacks: true);
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
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: surfaceColor,
              borderRadius: BorderRadius.circular(10),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: _isResponding
                  ? _buildRespondingSurface(context)
                  : _isCompacting
                  ? _buildCompactSurface(context)
                  : _buildActivitySurface(context),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRespondingSurface(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final phaseLabel = context.conversationActivityLabel(_view);
    final parts = _view.responseParts;
    return Semantics(
      container: true,
      liveRegion: true,
      label: phaseLabel,
      child: Padding(
        key: const ValueKey('conversation-activity'),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHeaderRow(
              context,
              phaseLabel: phaseLabel,
              expandable: false,
              isExpanded: false,
            ),
            if (parts.isNotEmpty) ...[
              const SizedBox(height: 5),
              ConstrainedBox(
                key: const ValueKey('conversation-activity-response-stream'),
                constraints: BoxConstraints(
                  maxHeight: widget.maxResponseHeight,
                ),
                child: Scrollbar(
                  controller: _responseScrollController,
                  thumbVisibility: true,
                  child: SingleChildScrollView(
                    controller: _responseScrollController,
                    primary: false,
                    child: SelectionArea(
                      child: _ActivityMarkdownParts(
                        prefix: 'live-response-part',
                        parts: parts,
                        textColor: scheme.onSurface,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ],
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

  Widget _buildActivitySurface(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildTopHeaderRow(context),
        if (_expanded && _isExpandable) _buildExpandedArea(context),
      ],
    );
  }

  Widget _buildTopHeaderRow(BuildContext context) {
    final phaseLabel = context.conversationActivityLabel(_view);
    final expandable = _isExpandable;
    final row = _buildHeaderRow(
      context,
      phaseLabel: phaseLabel,
      expandable: expandable,
      isExpanded: _expanded,
    );
    return Semantics(
      container: true,
      liveRegion: true,
      button: expandable,
      toggled: expandable ? _expanded : null,
      label: phaseLabel,
      child: Material(
        key: const ValueKey('conversation-activity'),
        type: MaterialType.transparency,
        child: expandable
            ? InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: _toggleTopExpanded,
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

    final detailText = _fallbackHeaderDetail();
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

  String? _fallbackHeaderDetail() {
    final err = _view.errorMessage?.trim();
    if (err != null && err.isNotEmpty) return err;
    if (_view.kind == ConversationActivityKind.runningTool &&
        _view.activeTools.isNotEmpty &&
        _view.wait == null) {
      return _view.activeTools.last.singleLineLabel;
    }
    final summary = _view.summary?.trim();
    if (summary != null && summary.isNotEmpty) return summary;
    return null;
  }

  String? _trailingMetaText() {
    final toolCount = math.max(_view.activeToolCount, _view.activeTools.length);
    if (_hasReasoningBody && toolCount > 0) {
      return '×$toolCount';
    }
    if (toolCount > 1) {
      final foreground = toolCount - _view.backgroundToolCount;
      if (_view.backgroundToolCount > 0 && foreground <= 0) {
        return '×$toolCount';
      }
      return '×$toolCount';
    }
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
    final railColor = scheme.outlineVariant.withValues(alpha: 0.58);
    final reasoningParts = _view.reasoningParts;
    final tools = _visibleTools();
    final extraDetails = _extraDetails();
    final maxHeight = _effectiveMaxExpandedHeight(context);

    return ConstrainedBox(
      key: const ValueKey('conversation-activity-details'),
      constraints: BoxConstraints(
        minHeight: math.min(56.0, maxHeight),
        maxHeight: maxHeight,
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(15, 0, 10, 8),
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border(left: BorderSide(color: railColor, width: 1)),
          ),
          child: Padding(
            padding: const EdgeInsets.only(left: 11),
            child: Scrollbar(
              controller: _expandedScrollController,
              thumbVisibility: true,
              child: SingleChildScrollView(
                controller: _expandedScrollController,
                primary: false,
                child: SelectionArea(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (reasoningParts.isNotEmpty)
                        Padding(
                          key: const ValueKey(
                            'conversation-activity-thinking-full',
                          ),
                          padding: const EdgeInsets.only(top: 2, bottom: 4),
                          child: _ActivityMarkdownParts(
                            prefix: 'conversation-activity-thinking-part',
                            parts: reasoningParts,
                            textColor: scheme.onSurfaceVariant,
                          ),
                        ),
                      for (final tool in tools)
                        KeyedSubtree(
                          key: ValueKey('live-tool-slot-${tool.callId}'),
                          child: _LiveToolTile(
                            tool: tool.entry,
                            detail: tool.detail,
                            expanded: _expandedToolIds.contains(tool.callId),
                            elapsedSeconds: _elapsedSeconds(
                              tool.entry?.startedAt ?? tool.detail?.startedAt,
                            ),
                            onExpansionChanged: (expanded) {
                              setState(() {
                                if (expanded) {
                                  _expandedToolIds.add(tool.callId);
                                } else {
                                  _expandedToolIds.remove(tool.callId);
                                }
                              });
                            },
                          ),
                        ),
                      for (final detail in extraDetails)
                        _buildExtraDetailRow(context, detail),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<_LiveToolPresentation> _visibleTools() {
    final detailsById = <String, ThreadActivityToolDetail>{
      for (final detail in _view.toolDetails) detail.callId: detail,
    };
    final seen = <String>{};
    final out = <_LiveToolPresentation>[];
    for (final entry in _view.activeTools) {
      seen.add(entry.callId);
      out.add(
        _LiveToolPresentation(
          callId: entry.callId,
          entry: entry,
          detail: detailsById[entry.callId],
        ),
      );
    }
    for (final detail in _view.toolDetails) {
      if (seen.add(detail.callId)) {
        out.add(
          _LiveToolPresentation(
            callId: detail.callId,
            entry: null,
            detail: detail,
          ),
        );
      }
    }
    return out;
  }

  List<ConversationActivityDetail> _extraDetails() {
    final toolIds = <String>{
      for (final tool in _view.activeTools) tool.callId,
      for (final tool in _view.toolDetails) tool.callId,
    };
    return [
      for (final detail in _view.details)
        if (!detail.id.startsWith('reasoning:') &&
            !detail.id.startsWith('response:') &&
            !detail.id.startsWith('tool:') &&
            !toolIds.contains(detail.id))
          detail,
    ];
  }

  Widget _buildExtraDetailRow(
    BuildContext context,
    ConversationActivityDetail detail,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final body = detail.body;
    return Padding(
      key: ValueKey('conversation-activity-detail-${detail.id}'),
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (detail.hasTitle)
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Text(
                detail.title!,
                style: context.text.labelSmall?.copyWith(
                  fontFamily: studioCodeFontFamily,
                  color: scheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          if (body.isNotEmpty)
            Text(
              body,
              style: context.text.bodySmall?.copyWith(
                fontFamily: studioCodeFontFamily,
                fontSize: 11.5,
                color: scheme.onSurface,
                height: 1.38,
              ),
            ),
        ],
      ),
    );
  }

  int? _elapsedSeconds(int? startedAt) {
    if (startedAt == null) return null;
    final elapsed = DateTime.now().millisecondsSinceEpoch ~/ 1000 - startedAt;
    return elapsed < 0 ? 0 : elapsed;
  }
}

class _LiveToolPresentation {
  const _LiveToolPresentation({
    required this.callId,
    required this.entry,
    required this.detail,
  });

  final String callId;
  final ThreadActivityToolEntry? entry;
  final ThreadActivityToolDetail? detail;
}

class _LiveToolTile extends StatelessWidget {
  const _LiveToolTile({
    required this.tool,
    required this.detail,
    required this.expanded,
    required this.elapsedSeconds,
    required this.onExpansionChanged,
  });

  final ThreadActivityToolEntry? tool;
  final ThreadActivityToolDetail? detail;
  final bool expanded;
  final int? elapsedSeconds;
  final ValueChanged<bool> onExpansionChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final callId = tool?.callId ?? detail!.callId;
    final title = (tool?.singleLineLabel ?? detail?.name ?? callId).trim();
    final arguments = detail?.arguments;
    final outputParts = detail?.outputParts;
    final hasArguments = arguments != null && arguments.isNotEmpty;
    final parts = outputParts ?? const <ThreadActivityToolOutputPart>[];
    final canExpand = hasArguments || parts.any((part) => part.text.isNotEmpty);
    final summaryStyle = context.text.bodySmall?.copyWith(
      fontFamily: studioCodeFontFamily,
      fontSize: 12,
      letterSpacing: 0.1,
      color: scheme.onSurface,
      height: 1.3,
    );
    final metaStyle = context.text.labelSmall?.copyWith(
      fontFamily: studioCodeFontFamily,
      fontSize: 11,
      letterSpacing: 0.2,
      fontFeatures: const [FontFeature.tabularFigures()],
      color: scheme.onSurfaceVariant.withValues(alpha: 0.78),
      height: 1.2,
    );

    final titleRow = Row(
      children: [
        Expanded(
          child: Text(
            title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: summaryStyle,
          ),
        ),
        if (elapsedSeconds != null) ...[
          const SizedBox(width: 8),
          Text(
            '${elapsedSeconds}s',
            key: ValueKey('live-tool-elapsed-$callId'),
            style: metaStyle,
          ),
        ],
      ],
    );

    if (!canExpand) {
      return Padding(
        key: ValueKey('live-tool-slot-$callId'),
        padding: const EdgeInsets.symmetric(vertical: 3.5, horizontal: 2),
        child: titleRow,
      );
    }

    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        key: ValueKey('live-tool-row-$callId'),
        initiallyExpanded: expanded,
        onExpansionChanged: onExpansionChanged,
        dense: true,
        minTileHeight: 28,
        tilePadding: const EdgeInsets.symmetric(horizontal: 2),
        childrenPadding: const EdgeInsets.only(left: 8, right: 2, bottom: 8),
        expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
        shape: const Border(),
        collapsedShape: const Border(),
        title: titleRow,
        children: [
          KeyedSubtree(
            key: ValueKey('live-tool-details-$callId'),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (hasArguments)
                  StudioCodeBlock(
                    text: arguments,
                    language: context.l10n.timelineToolArguments,
                    horizontalScroll: false,
                    maxHeight: 160,
                    margin: const EdgeInsets.only(top: 4),
                    padding: const EdgeInsets.all(10),
                  ),
                for (var index = 0; index < parts.length; index++)
                  StudioCodeBlock(
                    key: ValueKey(
                      'live-tool-output-$callId-${parts[index].partId}',
                    ),
                    text: parts[index].text,
                    language: index == 0
                        ? context.l10n.timelineToolOutput
                        : null,
                    horizontalScroll: false,
                    maxHeight: 180,
                    margin: EdgeInsets.only(
                      top: hasArguments || index > 0 ? 6 : 4,
                    ),
                    padding: const EdgeInsets.all(10),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
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
    final textStyle = context.text.bodySmall?.copyWith(
      color: color,
      fontWeight: fontWeight,
      letterSpacing: 0.1,
      height: 1.25,
    );
    return TimelineMarkdown(
      id: 'live-inline-md-$id',
      text: inlineText,
      style: textStyle,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      onLink: (_) {},
      isSafeLink: (_) => false,
      imageBuilder: (_, url) => Text(url),
    );
  }
}

class _ActivityMarkdownParts extends StatelessWidget {
  const _ActivityMarkdownParts({
    required this.prefix,
    required this.parts,
    required this.textColor,
  });

  final String prefix;
  final List<ThreadActivityContentPart> parts;
  final Color textColor;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final part in parts)
          KeyedSubtree(
            key: ValueKey('$prefix-${part.itemId}'),
            child: _MarkdownBodyBlock(
              id: '$prefix-${part.itemId}',
              markdown: part.text,
              textColor: textColor,
            ),
          ),
      ],
    );
  }
}

class _MarkdownBodyBlock extends StatelessWidget {
  const _MarkdownBodyBlock({
    required this.id,
    required this.markdown,
    required this.textColor,
  });

  final String id;
  final String markdown;
  final Color textColor;

  @override
  Widget build(BuildContext context) {
    final textStyle = context.text.bodySmall?.copyWith(
      color: textColor,
      height: 1.45,
    );
    return TimelineMarkdown(
      id: 'live-body-md-$id',
      text: markdown,
      style: textStyle,
      onLink: (_) {},
      isSafeLink: (_) => false,
      imageBuilder: (_, url) => Text(url),
    );
  }
}
