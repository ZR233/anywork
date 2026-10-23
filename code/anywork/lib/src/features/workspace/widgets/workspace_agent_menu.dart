import 'package:anywork_client/resources.dart';
import 'package:anywork_client/workspace.dart';
import 'package:flutter/material.dart';

import '../../../app/theme/studio_tokens.dart';
import '../../../diagnostics/studio_driver_keys.dart';
import '../../../l10n/studio_l10n.dart';

class WorkspaceAgentMenu extends StatefulWidget {
  const WorkspaceAgentMenu({
    required this.agents, required this.complete, required this.loading,
    required this.current, required this.selectedThreadId, required this.enabled,
    required this.onSelect, required this.onLoadMore, super.key,
  });
  final List<AgentDirectoryEntry> agents;
  final bool complete;
  final bool loading;
  final bool current;
  final bool enabled;
  final String? selectedThreadId;
  final ValueChanged<String> onSelect;
  final VoidCallback onLoadMore;

  @override
  State<WorkspaceAgentMenu> createState() => _WorkspaceAgentMenuState();
}

class _WorkspaceAgentMenuState extends State<WorkspaceAgentMenu> {
  final _controller = MenuController();

  @override
  Widget build(BuildContext context) {
    final indexed = [for (var i = 0; i < widget.agents.length; i++) (i, widget.agents[i])]
      ..sort((a, b) {
        final priority = _priority(a.$2.state).compareTo(_priority(b.$2.state));
        return priority == 0 ? a.$1.compareTo(b.$1) : priority;
      });
    final viewport = MediaQuery.sizeOf(context);
    final available = (viewport.width - 24).clamp(0.0, double.infinity).toDouble();
    final minimum = available < 240 ? available : 240.0;
    final width = (viewport.width * .36).clamp(minimum, available).toDouble();
    final height = (viewport.height - 96).clamp(0.0, 320.0).toDouble();
    final knownFault = widget.agents.any((agent) => _error(agent.state) != null);
    final waiting = widget.agents.any((agent) => agent.state is WaitingInteractionAgentState);
    final active = widget.agents.any((agent) => _priority(agent.state) == 0);
    final aggregate = knownFault ? context.colors.error
        : waiting ? context.statusColors.warning
        : active ? context.statusColors.activeIndicator
        : widget.current && widget.complete ? context.statusColors.success
        : context.colors.onSurfaceVariant;
    return MenuAnchor(
      controller: _controller, crossAxisUnconstrained: false,
      style: MenuStyle(
        minimumSize: WidgetStatePropertyAll(Size(width, 0)),
        maximumSize: WidgetStatePropertyAll(Size(width, height))),
      alignmentOffset: const Offset(6, 6),
      menuChildren: [
        for (final entry in indexed) _row(context, entry.$2),
        if (widget.agents.isEmpty && widget.complete)
          MenuItemButton(child: Text(context.l10n.statusAgentsCount(0))),
        if (widget.loading) MenuItemButton(child: Text(context.l10n.workspaceLoading)),
        if (!widget.complete) MenuItemButton(
          onPressed: widget.loading || !widget.enabled ? null : widget.onLoadMore,
          leadingIcon: const Icon(Icons.expand_more), child: Text(MaterialLocalizations.of(context).moreButtonTooltip)),
      ],
      child: TextButton(key: StudioDriverKeys.agentSwitcher,
        onPressed: () => _controller.isOpen ? _controller.close() : _controller.open(),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.circle, size: 6, color: aggregate),
          const SizedBox(width: 8),
          Text('${context.l10n.statusAgentsCount(widget.agents.length)}${widget.complete ? '' : '…'}'),
          const SizedBox(width: 4),
          const Icon(Icons.keyboard_arrow_down, size: 14),
        ])),
    );
  }

  Widget _row(BuildContext context, AgentDirectoryEntry agent) {
    final error = _error(agent.state);
    final retired = agent.parentPath != null && agent.role == 'planner';
    final task = agent.task.trim();
    final summary = task.isNotEmpty ? task
        : retired ? agent.threadId : context.roleLabel(agent.role);
    final status = error == null ? context.threadStatusLabel(_status(agent.state))
        : '${error.message}\n${error.code}';
    final selected = widget.selectedThreadId == agent.threadId;
    final secondary = context.text.labelSmall?.copyWith(color: context.colors.onSurfaceVariant);
    return MenuItemButton(key: StudioDriverKeys.agentRow(agent.threadId),
      onPressed: widget.enabled && widget.current ? () => widget.onSelect(agent.threadId) : null,
      style: MenuItemButton.styleFrom(backgroundColor: selected ? context.colors.surfaceContainerHigh : null),
      leadingIcon: Padding(padding: EdgeInsetsDirectional.only(start: agent.depth * 12.0),
        child: Icon(error != null ? Icons.error_outline : Icons.circle,
          size: error != null ? 16 : 9,
          color: error != null ? context.colors.error
              : !widget.current ? context.colors.onSurfaceVariant
              : agent.state is WaitingInteractionAgentState ? context.statusColors.warning
              : _priority(agent.state) == 0 ? context.statusColors.activeIndicator
              : context.statusColors.success)),
      trailingIcon: Visibility(visible: selected,
        maintainSize: true, maintainAnimation: true, maintainState: true,
        child: const Icon(Icons.check, size: 18)),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Flexible(flex: 2, child: Column(mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start, children: [
            Tooltip(message: summary, child: Text(summary,
              key: StudioDriverKeys.agentTaskSummary(agent.threadId),
              maxLines: 1, overflow: TextOverflow.ellipsis)),
            if (agent.role.trim().isNotEmpty) Text(retired ? context.l10n.agentRoleRetired
                : context.roleLabel(agent.role),
              maxLines: 1, overflow: TextOverflow.ellipsis, style: secondary),
          ])),
        const SizedBox(width: 12),
        Flexible(child: Tooltip(message: status,
          child: Text(status, maxLines: 1, overflow: TextOverflow.ellipsis, style: secondary))),
      ]),
    );
  }
}

int _priority(AgentState state) => switch (state) {
  QueuedAgentState() || RunningAgentState() || WaitingToolAgentState() ||
  WaitingInteractionAgentState() || CancellingAgentState() => 0,
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
