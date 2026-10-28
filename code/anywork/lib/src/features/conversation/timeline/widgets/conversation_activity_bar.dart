import 'dart:async';
import 'dart:math' as math;

import 'package:anywork_client/studio_client.dart';
import 'package:flutter/material.dart';

import '../../../../app/theme/studio_tokens.dart';
import '../../../../l10n/studio_l10n.dart';
import '../../../../shared/studio_driver_keys.dart';
import 'conversation_live_status_adapter.dart';
import 'conversation_live_status_models.dart';
import 'reasoning_summary.dart';
import 'timeline_markdown.dart';

export 'conversation_live_status_adapter.dart';
export 'conversation_live_status_models.dart';
export 'conversation_live_tool_specs.dart';

/// 会话聊天框上方的实时状态栏组件。
///
/// 支持两种驱动模式：
/// 1. **纯 Dart 独立控制器模式（[ConversationActivityBar.fromController]）**：
///    直接注入 [ConversationLiveStatusController]，通过喂入 `sealed`
///    [ConversationLiveStatusMessage] 驱动全部阶段、粘性思考摘要、流式思考尾部截断、
///    泛型工具槽位与流式回复文本，无需 Rust Bridge、`ProviderScope` 或 `AnyworkClient`，
///    可直接用于官方 Flutter Widget Preview 与纯 Dart 单元测试。
/// 2. **视图同步模式（默认构造函数 [ConversationActivityBar]）**：
///    接收 [ConversationActivityView]，内部自动通过 [ConversationLiveStatusAdapter]
///    将其转换为 [ConversationLiveStatusMessage] 同步到内部控制器。
class ConversationActivityBar extends StatefulWidget {
  const ConversationActivityBar({
    required this.view,
    this.onExpand,
    this.onCollapse,
    this.onExpandedChanged,
    this.maxExpandedHeight = 220,
    this.maxResponseHeight = 180,
    super.key,
  }) : controller = null;

  const ConversationActivityBar.fromController({
    required ConversationLiveStatusController this.controller,
    this.onExpand,
    this.onCollapse,
    this.onExpandedChanged,
    this.maxExpandedHeight = 220,
    this.maxResponseHeight = 180,
    super.key,
  }) : view = null;

  final ConversationActivityView? view;
  final ConversationLiveStatusController? controller;
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
  ConversationLiveStatusController? _internalController;
  final ScrollController _expandedScrollController = ScrollController();
  final ScrollController _responseScrollController = ScrollController();
  Timer? _ticker;
  bool? _lastReportedExpanded;

  ConversationLiveStatusController get _effectiveController =>
      widget.controller ?? _internalController!;

  @override
  void initState() {
    super.initState();
    if (widget.controller == null) {
      _internalController = ConversationLiveStatusController();
      ConversationLiveStatusAdapter.syncFromView(
        _internalController!,
        widget.view,
      );
    }
    _effectiveController.addListener(_onControllerChanged);
    _syncTicker();
    _reportExpandedIfChanged();
  }

  @override
  void didUpdateWidget(covariant ConversationActivityBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller?.removeListener(_onControllerChanged);
      if (widget.controller == null) {
        _internalController ??= ConversationLiveStatusController();
        ConversationLiveStatusAdapter.syncFromView(
          _internalController!,
          widget.view,
        );
      } else {
        _internalController?.dispose();
        _internalController = null;
      }
      _effectiveController.addListener(_onControllerChanged);
    } else if (widget.controller == null && oldWidget.view != widget.view) {
      final prevIdentity = _effectiveController.identity;
      ConversationLiveStatusAdapter.syncFromView(
        _effectiveController,
        widget.view,
      );
      if (_effectiveController.identity != prevIdentity) {
        widget.onCollapse?.call();
      }
    }
    _syncTicker();
    _reportExpandedIfChanged();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _effectiveController.removeListener(_onControllerChanged);
    if (_lastReportedExpanded == true) {
      widget.onCollapse?.call();
    }
    widget.onExpandedChanged?.call(false);
    _internalController?.dispose();
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

  void _onControllerChanged() {
    if (!mounted) return;
    _syncTicker();
    _reportExpandedIfChanged();
    setState(() {});
  }

  void _syncTicker() {
    if (_effectiveController.hasActiveTimer) {
      _ticker ??= Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) {
          _effectiveController.notifyTick();
        }
      });
    } else {
      _ticker?.cancel();
      _ticker = null;
    }
  }

  void _reportExpandedIfChanged() {
    final current = _effectiveController.expanded;
    if (_lastReportedExpanded == current) return;
    _lastReportedExpanded = current;
    widget.onExpandedChanged?.call(current);
  }

  void _toggleTopExpanded() {
    final ctrl = _effectiveController;
    if (!ctrl.isExpandable) return;
    final next = !ctrl.expanded;
    ctrl.setExpanded(next);
    if (next) {
      widget.onExpand?.call();
    } else {
      widget.onCollapse?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = _effectiveController;
    if (ctrl.phase == ConversationLivePhase.idle) {
      return const SizedBox.shrink();
    }
    final scheme = Theme.of(context).colorScheme;
    final isIssue = ctrl.phase == ConversationLivePhase.storageBlocked;
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
              child: ctrl.phase == ConversationLivePhase.responding
                  ? _buildRespondingSurface(context, ctrl)
                  : _buildActivitySurface(context, ctrl),
            ),
          ),
        ),
      ),
    );
  }

  /// `responding` 阶段：文本输出直接流式展示全部内容，动态增高状态栏，
  /// 达到最大高度后内部可滚动，**不可展开，没有展开的内容**。
  Widget _buildRespondingSurface(
    BuildContext context,
    ConversationLiveStatusController ctrl,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final text = ctrl.responseStreamText;
    final phaseLabel = _phaseLabel(context, ctrl);
    return Semantics(
      container: true,
      liveRegion: true,
      label: phaseLabel,
      child: Padding(
        key: StudioDriverKeys.conversationActivity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                _buildLeadingIndicator(context, ctrl, scheme.primary),
                const SizedBox(width: 8),
                Text(
                  phaseLabel,
                  style: context.text.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                    height: 1.2,
                  ),
                ),
              ],
            ),
            if (text.isNotEmpty) ...[
              const SizedBox(height: 5),
              Flexible(
                fit: FlexFit.loose,
                child: ConstrainedBox(
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
                        child: _MarkdownBodyBlock(
                          id: 'live-response-${ctrl.identity}',
                          markdown: text,
                          textColor: scheme.onSurface,
                        ),
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

  Widget _buildActivitySurface(
    BuildContext context,
    ConversationLiveStatusController ctrl,
  ) {
    final isExpanded = ctrl.expanded;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildTopHeaderRow(context, ctrl),
        if (isExpanded)
          Flexible(
            fit: FlexFit.loose,
            child: _buildExpandedArea(context, ctrl),
          ),
      ],
    );
  }

  Widget _buildTopHeaderRow(
    BuildContext context,
    ConversationLiveStatusController ctrl,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final isIssue = ctrl.phase == ConversationLivePhase.storageBlocked;
    final tone = isIssue ? scheme.error : scheme.onSurface;
    final muted = isIssue ? scheme.error : scheme.onSurfaceVariant;
    final expandable = ctrl.isExpandable;
    final isExpanded = ctrl.expanded;
    final phaseLabel = _phaseLabel(context, ctrl);

    final Widget content = _buildHeaderContent(
      context,
      ctrl,
      phaseLabel: phaseLabel,
      tone: tone,
      muted: muted,
    );

    final row = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6.5),
      child: Row(
        children: [
          _buildLeadingIndicator(context, ctrl, isIssue ? scheme.error : muted),
          const SizedBox(width: 8),
          Expanded(child: content),
          if (_trailingMetaText(ctrl) case final trailingMeta?) ...[
            const SizedBox(width: 8),
            Text(
              trailingMeta,
              key: const ValueKey('conversation-activity-trailing-meta'),
              style: context.text.labelSmall?.copyWith(
                fontFamily: studioCodeFontFamily,
                fontSize: 11,
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

    return Semantics(
      container: true,
      liveRegion: true,
      button: expandable,
      toggled: expandable ? isExpanded : null,
      label: phaseLabel,
      child: Material(
        key: StudioDriverKeys.conversationActivity,
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

  Widget _buildHeaderContent(
    BuildContext context,
    ConversationLiveStatusController ctrl, {
    required String phaseLabel,
    required Color tone,
    required Color muted,
  }) {
    // 1. 若存在粘性思考摘要（且当前并非等待子代理/定时器专门等待行），最外层固定用 Markdown 展示该思考摘要，
    //    直到新的思考摘要出现才替换。
    if (ctrl.hasStickyThinkingSummary && ctrl.wait == null) {
      final summaryMd = ctrl.thinkingSummaryMarkdown!;
      final seconds = ctrl.thinkingElapsedSeconds;
      final prefix = seconds != null && seconds > 0 ? '思考了 $seconds 秒' : null;
      return Row(
        key: const ValueKey('conversation-activity-sticky-summary'),
        children: [
          if (prefix != null) ...[
            Text(
              prefix,
              style: context.text.bodySmall?.copyWith(
                color: tone,
                fontWeight: FontWeight.w600,
                height: 1.25,
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 5),
              child: Text(
                '·',
                style: context.text.bodySmall?.copyWith(
                  color: muted,
                  height: 1.25,
                ),
              ),
            ),
          ],
          Expanded(
            child: _InlineSummaryMarkdown(
              id: 'sticky-summary-${ctrl.identity}',
              markdown: summaryMd,
              color: prefix == null ? tone : muted,
              fontWeight: prefix == null ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ],
      );
    }

    // 2. 若无思考摘要但处于流式思考中：显示一行流式更新的思考内容，不断更新截断前面部分。
    if (ctrl.hasStreamingThinkingWithoutSummary) {
      final truncatedTail = ctrl.frontTruncatedThinkingLine(maxChars: 72);
      return Row(
        children: [
          Text(
            phaseLabel,
            style: context.text.bodySmall?.copyWith(
              color: tone,
              fontWeight: FontWeight.w600,
              height: 1.25,
            ),
          ),
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
            child: _FrontTruncatedSingleLineStream(
              key: const ValueKey(
                'conversation-activity-thinking-stream-single-line',
              ),
              text: truncatedTail,
              fullSingleLineText: ctrl.singleLineThinkingStream,
              style: context.text.bodySmall?.copyWith(
                color: muted,
                height: 1.25,
              ),
            ),
          ),
        ],
      );
    }

    // 3. 常规阶段（如正在压缩、准备中、无摘要时的工具执行或等待）：
    final String? detailText = _fallbackHeaderDetail(context, ctrl);
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
                fontFamily: ctrl.phase == ConversationLivePhase.runningTool
                    ? studioCodeFontFamily
                    : null,
                color: muted,
                height: 1.25,
              ),
            ),
          ),
        ],
      ],
    );
  }

  String? _fallbackHeaderDetail(
    BuildContext context,
    ConversationLiveStatusController ctrl,
  ) {
    final err = ctrl.errorMessage?.trim();
    if (err != null && err.isNotEmpty) return err;
    if (ctrl.phase == ConversationLivePhase.runningTool &&
        ctrl.latestActiveTool != null &&
        ctrl.wait == null) {
      return ctrl.latestActiveTool!.buildSummaryLabel(context);
    }
    final summary = ctrl.phaseSummary?.trim();
    if (summary != null && summary.isNotEmpty) return summary;
    return null;
  }

  String? _trailingMetaText(ConversationLiveStatusController ctrl) {
    final toolCount = ctrl.activeToolCount;
    if (ctrl.hasStickyThinkingSummary && toolCount > 0) {
      return '$toolCount 项工具执行中';
    }
    if (toolCount > 1) {
      final foreground = toolCount - ctrl.backgroundToolCount;
      if (ctrl.backgroundToolCount > 0 && foreground <= 0) {
        return '后台 $toolCount';
      }
      return '×$toolCount';
    }
    if (ctrl.phase == ConversationLivePhase.runningTool &&
        ctrl.latestActiveTool != null) {
      final secs = ctrl.elapsedSecondsForTool(ctrl.latestActiveTool!.callId);
      return '${secs}s';
    }
    if (ctrl.phase == ConversationLivePhase.thinking &&
        !ctrl.hasStickyThinkingSummary &&
        ctrl.thinkingElapsedSeconds != null &&
        ctrl.thinkingElapsedSeconds! > 0) {
      return '${ctrl.thinkingElapsedSeconds}s';
    }
    return null;
  }

  /// 展开内容区：
  /// - 沿左侧 `1px` 竖向引导线排布，无任何卡片框或胶囊；
  /// - 限制最大高度（并满足 최소高度 >= 48px），内容超出时显示滚动条；
  /// - 内部展示正在执行的工具列表（每项显示已执行秒数并可二次展开详情）及完整思考正文。
  Widget _buildExpandedArea(
    BuildContext context,
    ConversationLiveStatusController ctrl,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final railColor = scheme.outlineVariant.withValues(alpha: 0.58);
    final tools = ctrl.activeTools;
    final thinkingFull = ctrl.thinkingStreamText;
    final extraDetails = ctrl.extraDetails;
    final maxHeight = _effectiveMaxExpandedHeight(context);

    return ConstrainedBox(
      key: StudioDriverKeys.conversationActivityDetails,
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
                      if (thinkingFull.isNotEmpty)
                        Padding(
                          key: const ValueKey(
                            'conversation-activity-thinking-full',
                          ),
                          padding: const EdgeInsets.only(top: 2, bottom: 4),
                          child: _MarkdownBodyBlock(
                            id: 'thinking-full-${ctrl.identity}',
                            markdown: thinkingFull,
                            textColor: scheme.onSurfaceVariant,
                          ),
                        ),
                      for (final slot in tools)
                        _buildRunningToolRow(context, ctrl, slot),
                      for (final detail in extraDetails)
                        _buildExtraDetailRow(context, detail),
                      if (ctrl.detailsLoading &&
                          tools.isEmpty &&
                          thinkingFull.isEmpty &&
                          extraDetails.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Row(
                            children: [
                              const SizedBox(
                                width: 12,
                                height: 12,
                                child: CircularProgressIndicator(
                                  key: ValueKey(
                                    'conversation-activity-details-loading',
                                  ),
                                  strokeWidth: 1.5,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                _phaseLabel(context, ctrl),
                                style: context.text.bodySmall?.copyWith(
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                      if (ctrl.detailsError != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            ctrl.detailsError!,
                            key: const ValueKey(
                              'conversation-activity-details-error',
                            ),
                            style: context.text.bodySmall?.copyWith(
                              color: scheme.error,
                              fontFamily: studioCodeFontFamily,
                            ),
                          ),
                        ),
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

  Widget _buildRunningToolRow(
    BuildContext context,
    ConversationLiveStatusController ctrl,
    LiveToolSlotView slot,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final canExpand = slot.isExpandable();
    final isToolExpanded = ctrl.isToolExpanded(slot.callId);
    final elapsedSecs = ctrl.elapsedSecondsForTool(slot.callId);
    final summary = slot.buildSummaryLabel(context);
    final subtitle = slot.buildSubtitleLabel(context);

    final rowContent = Padding(
      padding: const EdgeInsets.symmetric(vertical: 3.5, horizontal: 2),
      child: Row(
        children: [
          SizedBox(width: 16, child: Center(child: slot.buildLeading(context))),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              subtitle != null && subtitle.isNotEmpty
                  ? '$summary  $subtitle'
                  : summary,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.text.bodySmall?.copyWith(
                fontFamily: studioCodeFontFamily,
                fontSize: 12,
                color: scheme.onSurface,
                height: 1.3,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '${elapsedSecs}s',
            key: ValueKey('live-tool-elapsed-${slot.callId}'),
            style: context.text.labelSmall?.copyWith(
              fontFamily: studioCodeFontFamily,
              fontSize: 11,
              color: scheme.onSurfaceVariant.withValues(alpha: 0.78),
              height: 1.2,
            ),
          ),
          if (canExpand) ...[
            const SizedBox(width: 3),
            Icon(
              isToolExpanded
                  ? Icons.keyboard_arrow_up_rounded
                  : Icons.keyboard_arrow_right_rounded,
              size: 14,
              color: scheme.onSurfaceVariant,
            ),
          ],
        ],
      ),
    );

    return Column(
      key: ValueKey('live-tool-slot-${slot.callId}'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          key: ValueKey('live-tool-row-${slot.callId}'),
          type: MaterialType.transparency,
          child: canExpand
              ? InkWell(
                  borderRadius: BorderRadius.circular(4),
                  onTap: () => ctrl.toggleToolExpanded(slot.callId),
                  child: rowContent,
                )
              : rowContent,
        ),
        if (canExpand && isToolExpanded)
          KeyedSubtree(
            key: ValueKey('live-tool-details-${slot.callId}'),
            child: slot.buildExpandedDetails(
              context,
              elapsedSeconds: elapsedSecs,
            ),
          ),
      ],
    );
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

  Widget _buildLeadingIndicator(
    BuildContext context,
    ConversationLiveStatusController ctrl,
    Color color,
  ) {
    final waits =
        ctrl.phase == ConversationLivePhase.preparing ||
        ctrl.phase == ConversationLivePhase.compacting ||
        ctrl.phase == ConversationLivePhase.thinking ||
        ctrl.phase == ConversationLivePhase.runningTool ||
        ctrl.phase == ConversationLivePhase.awaitingApproval ||
        ctrl.phase == ConversationLivePhase.awaitingInput ||
        ctrl.phase == ConversationLivePhase.stopping;
    if (waits) {
      return SizedBox(
        width: 14,
        height: 14,
        child: Center(
          child: Container(
            key: const ValueKey('conversation-activity-pulse'),
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
        ),
      );
    }
    final icon = switch (ctrl.phase) {
      ConversationLivePhase.idle => Icons.circle_outlined,
      ConversationLivePhase.preparing => Icons.menu_book_outlined,
      ConversationLivePhase.compacting => Icons.compress_outlined,
      ConversationLivePhase.thinking => Icons.psychology_alt_outlined,
      ConversationLivePhase.planning => Icons.route_outlined,
      ConversationLivePhase.runningTool => Icons.build_outlined,
      ConversationLivePhase.awaitingApproval => Icons.verified_outlined,
      ConversationLivePhase.awaitingInput => Icons.help_outline,
      ConversationLivePhase.stopping => Icons.stop_circle_outlined,
      ConversationLivePhase.storageBlocked => Icons.error_outline,
      ConversationLivePhase.responding => Icons.edit_note_outlined,
    };
    return Icon(icon, size: 15, color: color);
  }

  String _phaseLabel(
    BuildContext context,
    ConversationLiveStatusController ctrl,
  ) {
    final l10n = context.l10n;
    final storage = ctrl.storage;
    return switch (ctrl.phase) {
      ConversationLivePhase.idle => '',
      ConversationLivePhase.preparing => l10n.conversationActivityPreparing,
      ConversationLivePhase.compacting => l10n.conversationActivityCompacting,
      ConversationLivePhase.thinking => l10n.timelineReasoningActive,
      ConversationLivePhase.responding => l10n.statusTurnResponding,
      ConversationLivePhase.planning => l10n.statusTurnPlanning,
      ConversationLivePhase.runningTool =>
        ctrl.wait == null
            ? l10n.conversationActivityRunningTool
            : switch (ctrl.wait!.intent) {
                ThreadWaitEventsIntentView(:final targets) =>
                  targets.isEmpty
                      ? l10n.conversationActivityWaitingMessages
                      : l10n.conversationActivityWaitingTools,
                ThreadWaitTimerIntentView() =>
                  l10n.conversationActivityWaitingTimer,
              },
      ConversationLivePhase.awaitingApproval =>
        l10n.statusInteractionToolApproval,
      ConversationLivePhase.awaitingInput => l10n.statusInteractionUserInput,
      ConversationLivePhase.stopping => l10n.conversationActivityStopping,
      ConversationLivePhase.storageBlocked =>
        storage == null
            ? l10n.conversationActivitySaveFailed
            : storage.resumeRequired && storage.canResume
            ? l10n.conversationActivityResumeReady
            : storage.hasFault
            ? l10n.conversationActivitySaveFailed
            : storage.pressurePaused
            ? l10n.conversationActivityStoragePressure
            : storage.execution != ThreadStorageExecution.running
            ? l10n.conversationActivitySavePaused
            : l10n.conversationActivityResumeRequired,
    };
  }
}

/// 单行流式思考尾部视图：
/// 通过 `reverse: true` 的水平只读 `SingleChildScrollView` 始终对齐到流式最末尾，
/// 配合左侧渐隐遮罩与前向截断字符串，保证流式追加时不断更新并截断前面部分。
class _FrontTruncatedSingleLineStream extends StatelessWidget {
  const _FrontTruncatedSingleLineStream({
    required this.text,
    required this.fullSingleLineText,
    required this.style,
    super.key,
  });

  final String text;
  final String fullSingleLineText;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    return ShaderMask(
      shaderCallback: (bounds) => const LinearGradient(
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
        colors: [Colors.transparent, Colors.black, Colors.black],
        stops: [0.0, 0.08, 1.0],
      ).createShader(bounds),
      blendMode: BlendMode.dstIn,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        reverse: true,
        physics: const NeverScrollableScrollPhysics(),
        child: Text(text, maxLines: 1, softWrap: false, style: style),
      ),
    );
  }
}

/// 外层单行 Markdown 摘要渲染器（基于官方/主流 `GptMarkdown` 组件）。
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

/// 多行 Markdown 正文渲染器（用于展开区完整思考正文与 `responding` 流式文本输出）。
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
