import 'package:anywork_client/conversation.dart';
import 'package:anywork_client/resources.dart';
import 'package:flutter/material.dart';

import '../../../diagnostics/studio_driver_keys.dart';
import '../../../l10n/studio_l10n.dart';
import '../../../ui/status/status_bar_item.dart';
import '../state/read_material.dart';
import '../state/thread_status_state.dart';
import 'activity_semantics.dart';

enum StatusReadSection { activity, storage, configuration, workflow, turn }

class ThreadStatusView extends StatelessWidget {
  const ThreadStatusView({
    required this.state,
    required this.detailsBuilder,
    this.contextUsage,
    this.throughput,
    this.showPlanEntry = false,
    this.onOpenPlan,
    super.key,
  });
  final ThreadStatusViewState state;
  final WidgetBuilder detailsBuilder;

  /// Read-only context reading of the same Thread; it keeps its own consumer so
  /// context/timing updates never rebuild this bar.
  final Widget? contextUsage;

  /// Read-only throughput reading of the same Thread.
  final Widget? throughput;

  /// The approved Plan projection carries the only post-approval read entrance
  /// (design/13-plan.md §13.5): it lives in the chat status bar's「更多」menu,
  /// never as a second timeline row.
  final bool showPlanEntry;
  final VoidCallback? onOpenPlan;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Flexible(
        child: StatusBarItem(
          label: conversationActivityLabel(context, state),
          icon: conversationActivityIcon(state),
          detailBuilder: detailsBuilder,
        ),
      ),
      if (state.workflowRead.header?.currentRun case final run?)
        Flexible(
          child: StatusBarItem(
            label: state.workflowRead.textOf(run.currentStateTitle) ?? '—',
            icon: run.modeDeleted ? Icons.history : Icons.route_outlined,
          ),
        ),
      ?contextUsage,
      ?throughput,
      if (showPlanEntry) _StatusOverflow(onOpenPlan: onOpenPlan),
    ],
  );
}

/// The chat status bar's「更多」menu.
///
/// It only reopens the same published Plan document in the reading panel; it
/// owns no plan state, decision or local document copy, and is absent unless
/// the projection is approved with a current document.
class _StatusOverflow extends StatefulWidget {
  const _StatusOverflow({this.onOpenPlan});
  final VoidCallback? onOpenPlan;

  @override
  State<_StatusOverflow> createState() => _StatusOverflowState();
}

class _StatusOverflowState extends State<_StatusOverflow> {
  final MenuController _controller = MenuController();

  @override
  Widget build(BuildContext context) => MenuAnchor(
    key: const ValueKey('status-overflow'),
    controller: _controller,
    alignmentOffset: const Offset(6, 6),
    menuChildren: [
      MenuItemButton(
        key: StudioDriverKeys.statusPlanEntry,
        overflowAxis: Axis.vertical,
        onPressed: () {
          _controller.close();
          widget.onOpenPlan?.call();
        },
        child: Text(context.l10n.statusPlanEntry),
      ),
    ],
    builder: (context, controller, child) => IconButton(
      tooltip: MaterialLocalizations.of(context).moreButtonTooltip,
      onPressed: () {
        if (controller.isOpen) {
          controller.close();
        } else {
          controller.open();
        }
      },
      padding: EdgeInsets.zero,
      icon: const Icon(Icons.more_horiz, size: 18),
    ),
  );
}

class ThreadStatusDetailView extends StatelessWidget {
  const ThreadStatusDetailView({
    required this.state,
    required this.onLoadMore,
    required this.onReadText,
    required this.onWaitTargets,
    required this.onWaitTargetText,
    super.key,
  });
  final ThreadStatusViewState state;
  final ValueChanged<StatusReadSection> onLoadMore;
  final void Function(StatusReadSection, int) onReadText;
  final ValueChanged<int?> onWaitTargets;
  final void Function(int?, int) onWaitTargetText;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(conversationActivityLabel(context, state)),
      if (state.execution?.sync.error case final error?) Text(error.message),
      if (state.activityRead.header case final header?) ...[
        _text(
          context,
          state.activityRead,
          header.summary,
          StatusReadSection.activity,
        ),
        if (header.latestStarted case final latest?) ...[
          _text(
            context,
            state.activityRead,
            latest.name,
            StatusReadSection.activity,
          ),
          _text(
            context,
            state.activityRead,
            latest.summary,
            StatusReadSection.activity,
          ),
          if (latest.wait case final wait?) _wait(context, wait, null),
        ],
        for (final tool in state.activityRead.items) ...[
          _text(
            context,
            state.activityRead,
            tool.name,
            StatusReadSection.activity,
          ),
          _text(
            context,
            state.activityRead,
            tool.summary,
            StatusReadSection.activity,
          ),
          if (tool.wait case final wait?) _wait(context, wait, tool.index),
        ],
        if (state.activityRead.nextOffset != null)
          _more(context, StatusReadSection.activity),
      ],
      if (state.storageRead.header case final storage?) ...[
        const Divider(),
        if (storage.lastError != null)
          _text(
            context,
            state.storageRead,
            storage.lastError!,
            StatusReadSection.storage,
          ),
        Text(
          '${storage.durableSequence ?? '—'} / ${storage.acceptedSequence ?? '—'}',
        ),
      ],
      if (state.configuration?.value case final config?) ...[
        const Divider(),
        Text(context.l10n.statusSkillsCount(config.activeSkillCount)),
        // Unsupported is unknown capability, never a healthy empty list/count.
        Text('${context.l10n.statusMcpSection} · —'),
        Text('${context.l10n.statusLspSection} · —'),
      ],
      if (state.configurationRead.header?.route case final route?) ...[
        _text(
          context,
          state.configurationRead,
          route.accountId,
          StatusReadSection.configuration,
        ),
        _text(
          context,
          state.configurationRead,
          route.modelId,
          StatusReadSection.configuration,
        ),
        if (route.effort != null)
          _text(
            context,
            state.configurationRead,
            route.effort!,
            StatusReadSection.configuration,
          ),
        if (route.unavailableReason != null)
          _text(
            context,
            state.configurationRead,
            route.unavailableReason!,
            StatusReadSection.configuration,
          ),
      ],
      for (final skill in state.configurationRead.items)
        _text(
          context,
          state.configurationRead,
          skill.name,
          StatusReadSection.configuration,
        ),
      if (state.configurationRead.nextOffset != null)
        _more(context, StatusReadSection.configuration),
      if (state.workflowRead.header?.currentRun case final run?) ...[
        const Divider(),
        _text(
          context,
          state.workflowRead,
          run.modeDisplayName,
          StatusReadSection.workflow,
        ),
        _text(
          context,
          state.workflowRead,
          run.currentStateTitle,
          StatusReadSection.workflow,
        ),
      ],
      if (state.turnRead.header case final turn?) ...[
        const Divider(),
        _text(context, state.turnRead, turn.id, StatusReadSection.turn),
        if (turn.state case FailedTurnRead(:final failure))
          _text(
            context,
            state.turnRead,
            failure.message,
            StatusReadSection.turn,
          ),
        if (turn.state case BudgetLimitedTurnRead(
          rollover: TurnReadRolloverFailed(:final error),
        ))
          _text(context, state.turnRead, error, StatusReadSection.turn),
      ],
      for (final failure in [
        state.activityRead.error,
        state.storageRead.error,
        state.configurationRead.error,
        state.workflowRead.error,
        state.turnRead.error,
      ])
        if (failure != null) Text(failure.message),
    ],
  );

  Widget _more(BuildContext context, StatusReadSection section) => TextButton(
    onPressed: () => onLoadMore(section),
    child: Text(context.l10n.timelineItemBodyLoad),
  );

  Widget _wait(BuildContext context, WaitReadValue wait, int? toolIndex) {
    final targets = toolIndex == null
        ? state.latestWaitTargets
        : state.waitTargetsByTool[toolIndex];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(wait.state.name),
        switch (wait.intent) {
          TimerWaitReadIntent(:final durationMs) => Text(
            context.l10n.timelineWaitTimerDuration('${durationMs}ms'),
          ),
          EventsWaitReadIntent(:final targetCount, :final timeoutMs) => Text(
            [
              context.l10n.timelineWaitTargetCount(targetCount),
              context.l10n.timelineWaitMaxDuration('${timeoutMs}ms'),
            ].join(' · '),
          ),
        },
        if (wait.messagesReady case final ready?)
          Text('${context.l10n.timelineWaitMessageSource} · $ready'),
        if (wait.intent is EventsWaitReadIntent && targets == null)
          TextButton(
            onPressed: () => onWaitTargets(toolIndex),
            child: Text(context.l10n.timelineItemBodyLoad),
          ),
        if (targets != null) ...[
          for (final target in targets.items)
            Padding(
              padding: const EdgeInsets.only(left: 12, bottom: 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _waitText(context, targets, target.taskId, toolIndex),
                  if (target.toolName case final name?)
                    _waitText(context, targets, name, toolIndex),
                  if (target.summary case final summary?)
                    _waitText(context, targets, summary, toolIndex),
                  if (target.status case final status?) Text(status.name),
                  if (target.summaryTruncated) const Text('…'),
                ],
              ),
            ),
          if (targets.loading) const LinearProgressIndicator(),
          if (targets.error case final error?) Text(error.message),
          if (targets.nextOffset != null)
            TextButton(
              onPressed: targets.loading
                  ? null
                  : () => onWaitTargets(toolIndex),
              child: Text(context.l10n.timelineItemBodyLoad),
            ),
        ],
      ],
    );
  }

  Widget _waitText(
    BuildContext context,
    ReadMaterial<WaitReadValue, WaitTargetReadItem> material,
    ReadText value,
    int? toolIndex,
  ) {
    final text = material.textOf(value);
    return text == null
        ? TextButton(
            onPressed: () => onWaitTargetText(
              toolIndex,
              (value as DeferredReadText).fieldId,
            ),
            child: Text(context.l10n.timelineItemBodyLoad),
          )
        : Text(text);
  }

  Widget _text<H, I>(
    BuildContext context,
    ReadMaterial<H, I> material,
    ReadText value,
    StatusReadSection section,
  ) {
    final text = material.textOf(value);
    return text == null
        ? TextButton(
            onPressed: () =>
                onReadText(section, (value as DeferredReadText).fieldId),
            child: Text(context.l10n.timelineItemBodyLoad),
          )
        : Text(text);
  }
}
