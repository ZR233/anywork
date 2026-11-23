import 'package:anywork_client/models.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../l10n/studio_l10n.dart';
import '../state/timeline_display_models.dart';
import '../widgets/completion_run_view.dart';
import '../widgets/conversation_activity_bar.dart';
import '../widgets/conversation_activity_viewport.dart';
import '../widgets/conversation_current_views.dart';
import '../widgets/timeline_activity_row.dart';
import '../widgets/timeline_activity_section.dart';
import 'live_status_header_spec.dart';
import 'live_status_state.dart';

/// 实时状态栏唯一纯 UI 表面：直接消费状态机输出 [LiveStatusGateState]。
///
/// 零 Riverpod、Client、AppGraph 或 FRB 依赖；生产连接层与官方预览共用同一套
/// 布局骨架，只通过可选 builder/slot 注入实时正文、工作组成员加载或交互面板。
class LiveStatusSurfaceView extends StatelessWidget {
  const LiveStatusSurfaceView({
    required this.gate,
    this.viewportKey,
    this.liveWorkBuilder,
    this.liveWorkChildBuilder,
    this.liveWorkInitiallyExpanded = false,
    this.responseBuilder,
    this.now,
    this.interactionDetailsSlot,
    this.onOpenActivityTools,
    this.onCloseActivityTools,
    this.onFirstActivityTools,
    this.onPreviousActivityTools,
    this.onNextActivityTools,
    this.onRetryError,
    super.key,
  });

  final LiveStatusGateState gate;
  final Key? viewportKey;
  final Widget Function(BuildContext context, LiveWorkPhase work)?
  liveWorkBuilder;
  final WidgetBuilder? liveWorkChildBuilder;
  final bool liveWorkInitiallyExpanded;
  final Widget Function(BuildContext context, LiveResponsePhase response)?
  responseBuilder;
  final DateTime Function()? now;
  final Widget? interactionDetailsSlot;
  final VoidCallback? onOpenActivityTools;
  final VoidCallback? onCloseActivityTools;
  final VoidCallback? onFirstActivityTools;
  final VoidCallback? onPreviousActivityTools;
  final VoidCallback? onNextActivityTools;
  final VoidCallback? onRetryError;

  @override
  Widget build(BuildContext context) {
    final details = gate.showInteractionDetails ? interactionDetailsSlot : null;
    final presenting = switch (gate) {
      LiveStatusIdle() || LiveStatusSuppressed() => null,
      LiveStatusPresenting(:final presentation) => presentation,
    };

    if (presenting == null) {
      if (details == null) return const SizedBox.shrink();
      return ConversationActivityViewport(
        key: viewportKey,
        children: [details],
      );
    }

    final barChildren = <Widget>[];

    switch (presenting.primary) {
      case LiveResponsePhase(:final activity) && final response:
        if (activity != null) {
          barChildren.add(
            Flexible(
              key: ValueKey(('live-primary-activity', activity.identity)),
              flex: 1,
              fit: FlexFit.loose,
              child: ConversationActivityStatus(view: activity),
            ),
          );
        }
        barChildren.add(
          Flexible(
            key: const ValueKey('live-primary-response'),
            flex: 3,
            fit: FlexFit.loose,
            child:
                responseBuilder?.call(context, response) ??
                ConversationResponseView(
                  startedAt: response.startedAt,
                  finishedAt: response.finishedAt,
                  active: response.isActive,
                  now: now,
                  child: ConversationCurrentWindowView(
                    id: 'live-response-preview',
                    text: response.previewText ?? '',
                  ),
                ),
          ),
        );
      case LiveCompactingPhase(:final activity):
        barChildren.add(
          Flexible(
            key: ValueKey(('live-primary-activity', activity.identity)),
            flex: 1,
            fit: FlexFit.loose,
            child: ConversationActivityStatus(view: activity),
          ),
        );
      case LiveWorkPhase() && final work:
        barChildren.add(
          Flexible(
            key: ValueKey(('live-work', work.id)),
            flex: 2,
            fit: FlexFit.loose,
            child: SingleChildScrollView(
              primary: false,
              child: _buildWorkGroup(context, work),
            ),
          ),
        );
      case LiveActivityPhase(:final activity):
        barChildren.add(
          Flexible(
            key: ValueKey(('live-primary-activity', activity.identity)),
            flex: 1,
            fit: FlexFit.loose,
            child: ConversationActivityStatus(view: activity),
          ),
        );
      case null:
        break;
    }

    for (var i = 0; i < presenting.attentions.length; i++) {
      final attention = presenting.attentions[i];
      final key = ValueKey(('live-attention', i));
      barChildren.add(
        Flexible(
          key: key,
          flex: 1,
          fit: FlexFit.loose,
          child: _buildAttention(context, attention),
        ),
      );
    }

    if (presenting.activityTools case final tools?) {
      barChildren.add(
        Flexible(
          key: const ValueKey('live-activity-tools-panel'),
          flex: 3,
          fit: FlexFit.loose,
          child: _ActivityToolsPanel(
            tools: tools,
            onOpen: onOpenActivityTools,
            onClose: onCloseActivityTools,
            onFirst: onFirstActivityTools,
            onPrevious: onPreviousActivityTools,
            onNext: onNextActivityTools,
          ),
        ),
      );
    }

    final viewportChildren = <Widget>[
      if (barChildren.isNotEmpty)
        ConversationActivityBar(children: barChildren),
      ?details,
    ];
    if (viewportChildren.isEmpty) return const SizedBox.shrink();

    return ConversationActivityViewport(
      key: viewportKey,
      children: viewportChildren,
    );
  }

  Widget _buildWorkGroup(BuildContext context, LiveWorkPhase work) {
    if (liveWorkBuilder case final builder?) {
      return builder(context, work);
    }
    return CompletionRunView(
      key: ValueKey(('live-work', work.id)),
      id: work.id,
      location: WorkDisplayLocation.live,
      state: DisplayBlockState.open,
      executionPresent: work.executionPresent,
      timing: work.timing,
      activity: work.activity,
      thinkingSummary: work.thinkingSummary,
      initiallyExpanded: liveWorkInitiallyExpanded,
      now: now,
      childBuilder: liveWorkChildBuilder ?? (_) => const SizedBox.shrink(),
    );
  }

  Widget _buildAttention(BuildContext context, LiveStatusAttention attention) =>
      switch (attention) {
        LiveStoppingAttention(:final activity) ||
        LiveApprovalAttention(
          :final activity,
        ) => ConversationActivityStatus(view: activity),
        LiveStorageAttention(:final activity, :final severity) =>
          ConversationActivityStatus(view: activity, storageSeverity: severity),
        LiveConnectionAttention() => _AttentionHeaderRow(
          spec: LiveStatusHeaderSpec.forAttention(context, attention),
        ),
        LiveErrorAttention(:final retryable) => _AttentionHeaderRow(
          spec: LiveStatusHeaderSpec.forAttention(context, attention),
          trailingAction: retryable && onRetryError != null
              ? TextButton(
                  onPressed: onRetryError,
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                  ),
                  child: Text(context.l10n.liveStatusRetryAction),
                )
              : null,
        ),
      };
}

class _AttentionHeaderRow extends StatelessWidget {
  const _AttentionHeaderRow({required this.spec, this.trailingAction});

  final LiveStatusHeaderSpec spec;
  final Widget? trailingAction;

  @override
  Widget build(BuildContext context) {
    final row = TimelineActivitySection(
      header: TimelineActivityRow(
        label: spec.label,
        icon: spec.icon,
        iconColor: spec.iconColor,
        labelColor: spec.labelColor,
        labelWidget: spec.labelWidget,
        indicatorStyle: spec.indicatorStyle,
        isIssue: spec.isIssue,
        active: spec.active,
        emphasized: spec.emphasized,
        expandable: false,
        header: true,
        tooltip: spec.tooltip,
        semanticsLabel: spec.semanticsLabel,
        meta: spec.meta,
      ),
    );
    if (trailingAction == null) return row;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(child: row),
        const SizedBox(width: 8),
        trailingAction!,
      ],
    );
  }
}

class _ActivityToolsPanel extends StatelessWidget {
  const _ActivityToolsPanel({
    required this.tools,
    this.onOpen,
    this.onClose,
    this.onFirst,
    this.onPrevious,
    this.onNext,
  });

  final LiveActivityToolsWindow tools;
  final VoidCallback? onOpen;
  final VoidCallback? onClose;
  final VoidCallback? onFirst;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    if (!tools.expanded) {
      return Align(
        alignment: AlignmentDirectional.centerStart,
        child: TextButton.icon(
          key: const ValueKey('live-activity-tools-open'),
          onPressed: onOpen,
          icon: const Icon(Icons.build_outlined, size: 16),
          label: Text(l10n.liveStatusActivityToolsTitle(tools.totalCount)),
        ),
      );
    }

    return SingleChildScrollView(
      primary: false,
      child: Padding(
        padding: const EdgeInsetsDirectional.only(top: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    l10n.liveStatusActivityToolsLoaded(
                      tools.loadedCount,
                      tools.totalCount,
                    ),
                    key: const ValueKey('live-activity-tools-count'),
                  ),
                ),
                TextButton(
                  key: const ValueKey('live-activity-tools-close'),
                  onPressed: onClose,
                  child: Text(l10n.liveStatusToolsCollapse),
                ),
              ],
            ),
            if (tools.error case final error?) Text(error.toString()),
            if (tools.loading)
              const LinearProgressIndicator()
            else
              for (final tool in tools.entries)
                TimelineActivityRow(
                  key: ValueKey(('live-activity-tool', tool.callId)),
                  icon: Icons.build_outlined,
                  indicatorStyle: tool.name == 'exec'
                      ? TimelineActivityIndicatorStyle.circularProgress
                      : TimelineActivityIndicatorStyle.restingCat,
                  active: tool.state != ThreadActivityToolState.finished,
                  expandable: false,
                  label: tool.singleLineLabel,
                  meta: context.toolStatusLabel(
                    tool.state == ThreadActivityToolState.finished
                        ? 'succeeded'
                        : tool.state.name,
                  ),
                ),
            Wrap(
              spacing: 8,
              children: [
                TextButton(
                  key: const ValueKey('live-activity-tools-first'),
                  onPressed: tools.hasPrevious ? onFirst : null,
                  child: Text(l10n.liveStatusToolsFirstPage),
                ),
                TextButton(
                  key: const ValueKey('live-activity-tools-previous'),
                  onPressed: tools.hasPrevious ? onPrevious : null,
                  child: Text(l10n.liveStatusToolsPreviousPage),
                ),
                TextButton(
                  key: const ValueKey('live-activity-tools-next'),
                  onPressed: tools.hasNext ? onNext : null,
                  child: Text(l10n.liveStatusToolsNextPage),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
