import 'package:anywork_client/resources.dart';
import 'package:anywork_client/workspace.dart';

import 'agent_membership.dart';

enum AgentListStopAction { none, stop, stopping, stoppedWaitingScheduling }

/// UI-only mapping of canonical row facts, never an execution/operation owner.
final class AgentListStopState {
  const AgentListStopState({required this.action, this.executionId});

  final AgentListStopAction action;
  final String? executionId;

  bool get canStop => action == AgentListStopAction.stop;
  bool get showsControl => action != AgentListStopAction.none;

  factory AgentListStopState.resolve({
    required AgentDirectoryEntry agent,
    String? acceptedExecutionId,
  }) {
    if (isRetiredAgentRow(agent) ||
        agent.state is ClosedAgentState ||
        agent.state is ClosingAgentState ||
        agent.state is FaultedAgentState) {
      return const AgentListStopState(action: AgentListStopAction.none);
    }
    final execution = agent.execution;
    if (execution != null &&
        (agent.state is CancellingAgentState ||
            execution.phase == AgentExecutionPhase.stopping ||
            execution.id == acceptedExecutionId)) {
      return AgentListStopState(
        action: AgentListStopAction.stopping,
        executionId: execution.id,
      );
    }
    // An Idle row may still own a preparing execution without a Turn.
    if (execution != null && agent.canStop) {
      return AgentListStopState(
        action: AgentListStopAction.stop,
        executionId: execution.id,
      );
    }
    // A directory notification cannot settle the ticket. Even an empty Idle
    // row keeps accepted stopping until the SDK proves original cleanup.
    if (execution == null && acceptedExecutionId != null) {
      return AgentListStopState(
        action: AgentListStopAction.stopping,
        executionId: acceptedExecutionId,
      );
    }
    if (agent.awaitingScheduling) {
      return const AgentListStopState(
        action: AgentListStopAction.stoppedWaitingScheduling,
      );
    }
    return const AgentListStopState(action: AgentListStopAction.none);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AgentListStopState &&
          action == other.action &&
          executionId == other.executionId;

  @override
  int get hashCode => Object.hash(action, executionId);
}

/// The rendered row's immutable input. The Repository validates this original
/// source/member again; selection and any currently active Session are absent.
final class AgentListStopTarget {
  const AgentListStopTarget({
    required this.origin,
    required this.member,
    required this.threadId,
    required this.executionId,
  });

  final ProductProjectionStamp origin;
  final ProductEntityRef member;
  final String threadId;
  final String executionId;

  bool belongsTo(AgentDirectoryState directory, AgentDirectoryEntry agent) {
    final mirror = directory.agents;
    if (directory.projection.stamp?.origin != origin.origin ||
        mirror is! CurrentCollectionMirror<AgentDirectoryEntry> ||
        mirror.window.origin != origin.origin ||
        agent.threadId != threadId ||
        (agent.execution != null && agent.execution!.id != executionId)) {
      return false;
    }
    final row = mirror.window.rows[member.entry];
    return row is ReadyReadValue<AgentDirectoryEntry, ProductEntityRef> &&
        row.current.origin == origin.origin &&
        row.current.reference.entry == member.entry &&
        row.current.value == agent;
  }

  static AgentListStopTarget? capture(
    AgentDirectoryState directory,
    AgentDirectoryEntry agent,
  ) {
    final stamp = directory.projection.stamp;
    final mirror = directory.agents;
    final stop = AgentListStopState.resolve(agent: agent);
    if (stamp == null ||
        directory.projection.sync.phase != ResourceSyncPhase.ready ||
        directory.projection.header?.source.brief is! ReadyObservedBrief ||
        mirror is! CurrentCollectionMirror<AgentDirectoryEntry> ||
        mirror.window.origin != stamp.origin ||
        !stop.canStop) {
      return null;
    }
    for (final member in mirror.window.entries) {
      final row = mirror.window.rows[member.entry];
      if (row is ReadyReadValue<AgentDirectoryEntry, ProductEntityRef> &&
          row.current.origin == stamp.origin &&
          row.current.reference == member &&
          row.current.value == agent) {
        return AgentListStopTarget(
          origin: stamp,
          member: member,
          threadId: agent.threadId,
          executionId: stop.executionId!,
        );
      }
    }
    return null;
  }
}
