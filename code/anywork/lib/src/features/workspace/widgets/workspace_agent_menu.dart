import 'package:anywork_client/operations.dart';
import 'package:anywork_client/resources.dart';
import 'package:anywork_client/workspace.dart';
import 'package:flutter/material.dart';

import '../../../app/theme/studio_tokens.dart';
import '../../../diagnostics/studio_driver_keys.dart';
import '../../../l10n/studio_l10n.dart';
import '../state/agent_list_stop.dart';
import '../state/agent_membership.dart';
import '../state/workspace_view_state.dart';

class WorkspaceAgentMenu extends StatefulWidget {
  const WorkspaceAgentMenu({
    required this.agents,
    required this.complete,
    required this.loading,
    required this.current,
    required this.selectedThreadId,
    required this.enabled,
    required this.onSelect,
    required this.onLoadMore,
    required this.onStop,
    this.threads = const {},
    this.stopActions = const {},
    super.key,
  });

  final List<AgentDirectoryEntry> agents;
  final bool complete;
  final bool loading;
  final bool current;
  final bool enabled;
  final String? selectedThreadId;
  final ValueChanged<String> onSelect;
  final VoidCallback onLoadMore;
  final ValueChanged<AgentDirectoryEntry> onStop;
  final Map<String, WorkspaceThreadRecord> threads;
  final Map<String, WorkspaceActionPresentation> stopActions;

  @override
  State<WorkspaceAgentMenu> createState() => _WorkspaceAgentMenuState();
}

class _WorkspaceAgentMenuState extends State<WorkspaceAgentMenu> {
  final _controller = MenuController();

  @override
  Widget build(BuildContext context) {
    final agents = AgentDirectoryQueries.menuOrder(widget.agents);
    final viewport = MediaQuery.sizeOf(context);
    final available = (viewport.width - 24)
        .clamp(0.0, double.infinity)
        .toDouble();
    final minimum = available < 240 ? available : 240.0;
    final width = (viewport.width * .36).clamp(minimum, available).toDouble();
    final height = (viewport.height - 96).clamp(0.0, 320.0).toDouble();
    final knownFault = widget.agents.any(
      (agent) => _error(agent.state) != null,
    );
    final waiting = widget.agents.any(
      (agent) => agent.state is WaitingInteractionAgentState,
    );
    final active = widget.agents.any((agent) => _priority(agent.state) == 0);
    final aggregate = knownFault
        ? context.colors.error
        : waiting
        ? context.statusColors.warning
        : active
        ? context.statusColors.activeIndicator
        : widget.current && widget.complete
        ? context.statusColors.success
        : context.colors.onSurfaceVariant;
    return MenuAnchor(
      controller: _controller,
      crossAxisUnconstrained: false,
      style: MenuStyle(
        minimumSize: WidgetStatePropertyAll(Size(width, 0)),
        maximumSize: WidgetStatePropertyAll(Size(width, height)),
      ),
      alignmentOffset: const Offset(6, 6),
      menuChildren: [
        for (final agent in agents) _row(context, agent, width),
        if (widget.agents.isEmpty && widget.complete)
          MenuItemButton(child: Text(context.l10n.statusAgentsCount(0))),
        if (widget.loading)
          MenuItemButton(child: Text(context.l10n.workspaceLoading)),
        if (!widget.complete)
          MenuItemButton(
            onPressed: widget.loading || !widget.enabled
                ? null
                : widget.onLoadMore,
            leadingIcon: const Icon(Icons.expand_more),
            child: Text(MaterialLocalizations.of(context).moreButtonTooltip),
          ),
      ],
      child: TextButton(
        key: StudioDriverKeys.agentSwitcher,
        onPressed: () =>
            _controller.isOpen ? _controller.close() : _controller.open(),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.circle, size: 6, color: aggregate),
            const SizedBox(width: 8),
            Text(
              '${context.l10n.statusAgentsCount(AgentDirectoryQueries.activeCount(agents))}${widget.complete ? '' : '…'}',
            ),
            const SizedBox(width: 4),
            const Icon(Icons.keyboard_arrow_down, size: 14),
          ],
        ),
      ),
    );
  }

  Widget _row(
    BuildContext context,
    AgentDirectoryEntry agent,
    double menuWidth,
  ) {
    final error = _error(agent.state);
    final retired = isRetiredAgentRow(agent);
    final thread = widget.threads[agent.threadId];
    final task = agent.task.trim();
    final summary = thread?.title.trim().isNotEmpty == true
        ? thread!.title
        : task.isNotEmpty
        ? task
        : retired
        ? agent.threadId
        : context.roleLabel(agent.role);
    final status = error == null
        ? context.threadStatusLabel(_status(agent.state))
        : '${error.message}\n${error.code}';
    final selected = widget.selectedThreadId == agent.threadId;
    final action = widget.stopActions[agent.threadId];
    final operation = action?.operation;
    final accepted =
        operation?.receipt != null || operation?.acknowledged == true;
    final stop = AgentListStopState.resolve(
      agent: agent,
      acceptedExecutionId: accepted && operation?.effective != true
          ? action?.directoryStopTarget?.executionId
          : null,
    );
    final frozen = agent.frozenModel ?? thread?.frozenModel;
    final model = frozen?.modelId ?? context.l10n.delegationModelNotRecorded;
    final modelTooltip = frozen == null
        ? model
        : '$model\n${frozen.accountId} / ${frozen.modelId}\n${context.l10n.statusReasoningEffort}: ${frozen.effort ?? context.l10n.statisticsReasoningEffortUnspecified}';
    final role = retired
        ? context.l10n.agentRoleRetired
        : context.roleLabel(agent.role);
    final indent = (agent.depth * 12.0)
        .clamp(0.0, (menuWidth - 208).clamp(0.0, menuWidth))
        .toDouble();
    final rowWidth = (menuWidth - 88 - indent).clamp(0.0, menuWidth).toDouble();
    final statusGap = rowWidth.clamp(0.0, 12.0).toDouble();
    final statusWidth = (rowWidth - statusGap).clamp(0.0, 84.0).toDouble();
    final secondary = context.text.labelSmall?.copyWith(
      color: context.colors.onSurfaceVariant,
    );
    final failures = <StudioFailure>{
      ?action?.admissionError,
      ?operation?.error,
      ?operation?.evidenceError,
      ?action?.observationError,
    };
    final failureText = failures.map(_failureText).join('\n');
    final rejected = action?.admissionError != null ||
        operation?.failurePhase == OperationFailurePhase.rejected;
    return MenuItemButton(
      key: StudioDriverKeys.agentRow(agent.threadId),
      onPressed: widget.enabled && widget.current
          ? () => widget.onSelect(agent.threadId)
          : null,
      style: MenuItemButton.styleFrom(
        backgroundColor: selected ? context.colors.surfaceContainerHigh : null,
      ),
      leadingIcon: Padding(
        padding: EdgeInsetsDirectional.only(start: indent),
        child: Icon(
          error != null ? Icons.error_outline : Icons.circle,
          size: error != null ? 16 : 9,
          color: error != null
              ? context.colors.error
              : !widget.current
              ? context.colors.onSurfaceVariant
              : agent.state is WaitingInteractionAgentState
              ? context.statusColors.warning
              : _priority(agent.state) == 0
              ? context.statusColors.activeIndicator
              : context.statusColors.success,
        ),
      ),
      trailingIcon: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _stopControl(context, agent, stop, action, summary),
          Visibility(
            visible: selected,
            maintainSize: true,
            maintainAnimation: true,
            maintainState: true,
            child: const Icon(Icons.check, size: 18),
          ),
        ],
      ),
      child: SizedBox(
        width: rowWidth,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Tooltip(
                    message: summary,
                    child: Text(
                      summary,
                      key: StudioDriverKeys.agentTaskSummary(agent.threadId),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                SizedBox(width: statusGap),
                SizedBox(
                  width: statusWidth,
                  child: Tooltip(
                    message: status,
                    child: Text(
                      status,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: secondary,
                    ),
                  ),
                ),
              ],
            ),
            Tooltip(
              message: modelTooltip,
              child: Text(
                '${agent.role.trim().isEmpty ? '' : '$role · '}$model',
                key: StudioDriverKeys.agentModel(agent.threadId),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: secondary,
              ),
            ),
            if (stop.action == AgentListStopAction.stopping ||
                stop.action == AgentListStopAction.stoppedWaitingScheduling)
              Text(
                stop.action == AgentListStopAction.stopping
                    ? context.l10n.agentStopping
                    : context.l10n.agentStopWaitingScheduling,
                key: StudioDriverKeys.agentStopNote(agent.threadId),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: secondary,
              ),
            if (_progress(context, action) case final progress?)
              Text(
                progress,
                key: operation?.failurePhase == OperationFailurePhase.unknownOutcome
                    ? ValueKey('agent-stop-unconfirmed-${agent.threadId}')
                    : ValueKey('agent-stop-progress-${agent.threadId}'),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: secondary,
              ),
            if (failures.isNotEmpty)
              Tooltip(
                message: failureText,
                child: Text(
                  rejected
                      ? context.l10n.agentStopFailed(failureText)
                      : context.l10n.conversationStopError(failureText),
                  key: ValueKey('agent-stop-failure-${agent.threadId}'),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: secondary?.copyWith(color: context.colors.error),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _stopControl(
    BuildContext context,
    AgentDirectoryEntry agent,
    AgentListStopState stop,
    WorkspaceActionPresentation? action,
    String summary,
  ) {
    if (!stop.canStop) return const SizedBox.shrink();
    final operation = action?.operation;
    final pending =
        action?.waiting == true ||
        operation?.isPending == true ||
        operation?.failurePhase == OperationFailurePhase.syncFailed ||
        ((operation?.receipt != null || operation?.acknowledged == true) &&
            operation?.effective != true);
    return IconButton(
      key: StudioDriverKeys.agentStop(agent.threadId),
      iconSize: 18,
      visualDensity: VisualDensity.compact,
      tooltip: context.l10n.agentStopSemantics(summary),
      onPressed: widget.enabled && widget.current && !pending
          ? () => widget.onStop(agent)
          : null,
      icon: pending
          ? const SizedBox.square(
              dimension: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.stop_circle_outlined),
    );
  }

  String? _progress(
    BuildContext context,
    WorkspaceActionPresentation? action,
  ) {
    final operation = action?.operation;
    if (operation?.failurePhase == OperationFailurePhase.unknownOutcome) {
      return context.l10n.conversationStopUnknown;
    }
    if (operation?.effective == true) {
      return context.l10n.conversationStopEffective;
    }
    if (operation?.observed == true) {
      return context.l10n.conversationStopObserved;
    }
    if (operation?.receipt != null || operation?.acknowledged == true) {
      return context.l10n.conversationStopAwaitingObservation;
    }
    return action?.waiting == true
        ? context.l10n.conversationStopRequesting
        : null;
  }
}

String _failureText(StudioFailure failure) =>
    '${failure.message}\n${failure.code.name} · ${failure.correlationId}';

int _priority(AgentState state) => switch (state) {
  QueuedAgentState() ||
  RunningAgentState() ||
  WaitingToolAgentState() ||
  WaitingInteractionAgentState() ||
  CancellingAgentState() => 0,
  FaultedAgentState() => 1,
  IdleAgentState() => 2,
  ClosingAgentState() || ClosedAgentState() => 3,
};

SourceStateError? _error(AgentState state) => switch (state) {
  FaultedAgentState(:final error) => error,
  ClosingAgentState(:final error) => error,
  _ => null,
};

ThreadStatus _status(AgentState state) => switch (state) {
  IdleAgentState() => ThreadStatus.idle,
  QueuedAgentState() => ThreadStatus.queued,
  RunningAgentState() => ThreadStatus.running,
  WaitingToolAgentState() => ThreadStatus.waitingTool,
  WaitingInteractionAgentState() => ThreadStatus.waitingInteraction,
  CancellingAgentState() => ThreadStatus.cancelling,
  ClosingAgentState() => ThreadStatus.closing,
  ClosedAgentState() => ThreadStatus.closed,
  FaultedAgentState() => ThreadStatus.faulted,
};
