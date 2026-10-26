import 'package:anywork_client/resources.dart';

import 'directory_state.dart';
import 'directory_values.dart';

/// Pure views of the canonical *complete* AgentDirectory. A Thread page or hot
/// Session set cannot create, remove or supply missing members for this query.
abstract final class AgentDirectoryQueries {
  /// Closed members remain in forRoot/menuOrder for read-only navigation.
  static int activeCount(List<AgentDirectoryEntry> agents) =>
      agents.where((agent) => agent.state is! ClosedAgentState).length;

  static String? rootThreadId({
    required String? threadId,
    required AgentDirectoryState directory,
  }) {
    if (threadId == null) return null;
    for (final agent in _members(directory)) {
      if (agent.threadId == threadId) return agent.rootThreadId;
    }
    return null;
  }

  /// Parent-first, preserving canonical sibling order and exact parent links.
  static List<AgentDirectoryEntry> forRoot({
    required String? rootThreadId,
    required AgentDirectoryState directory,
  }) {
    if (rootThreadId == null) return const [];
    final members = [
      for (final agent in _members(directory))
        if (agent.rootThreadId == rootThreadId) agent,
    ];
    final byParent = <String?, List<AgentDirectoryEntry>>{};
    for (final agent in members) {
      byParent.putIfAbsent(agent.parentPath, () => []).add(agent);
    }
    final result = <AgentDirectoryEntry>[];
    final seen = <String>{};
    // Iterative traversal also bounds stack use for an unusually deep tree.
    void append(AgentDirectoryEntry first) {
      final pending = <AgentDirectoryEntry>[first];
      while (pending.isNotEmpty) {
        final agent = pending.removeLast();
        if (!seen.add(agent.threadId)) continue;
        result.add(agent);
        pending.addAll(
          (byParent[agent.path] ?? const <AgentDirectoryEntry>[]).reversed,
        );
      }
    }

    for (final agent in members) {
      if (agent.threadId == rootThreadId) append(agent);
    }
    for (final agent in members) {
      append(agent);
    }
    return List.unmodifiable(result);
  }

  /// Status grouping does not disturb parent/sibling order within a group.
  static List<AgentDirectoryEntry> menuOrder(List<AgentDirectoryEntry> agents) {
    final indexed = [
      for (var index = 0; index < agents.length; index++)
        (index, agents[index]),
    ];
    indexed.sort((left, right) {
      final status = _priority(left.$2.state)
          .compareTo(_priority(right.$2.state));
      return status == 0 ? left.$1.compareTo(right.$1) : status;
    });
    return List.unmodifiable([for (final item in indexed) item.$2]);
  }

  static List<AgentDirectoryEntry> _members(AgentDirectoryState directory) {
    final mirror = directory.agents;
    if (directory.projection.sync.phase != ResourceSyncPhase.ready ||
        mirror is! CurrentCollectionMirror<AgentDirectoryEntry> ||
        mirror.window.origin != directory.projection.stamp?.origin ||
        directory.projection.header?.reference == null ||
        !mirror.window.complete ||
        mirror.window.entries.length != mirror.window.reference.total)
      throw _unavailable;
    final result = <AgentDirectoryEntry>[];
    final ids = <String>{};
    for (final reference in mirror.window.entries) {
      final row = mirror.window.rows[reference.entry];
      if (row is! ReadyReadValue<AgentDirectoryEntry, ProductEntityRef> ||
          row.current.origin != mirror.window.origin ||
          row.current.reference != reference)
        throw _unavailable;
      // A repeated Thread identity is one member. The canonical first delivery
      // owns its path/parent link and later repeats cannot duplicate it.
      if (!ids.add(row.current.value.threadId)) continue;
      result.add(row.current.value);
    }
    return result;
  }

  static int _priority(AgentState state) => switch (state) {
    QueuedAgentState() ||
    RunningAgentState() ||
    WaitingToolAgentState() ||
    WaitingInteractionAgentState() ||
    CancellingAgentState() => 0,
    FaultedAgentState() => 1,
    IdleAgentState() => 2,
    ClosingAgentState() || ClosedAgentState() => 3,
  };

  static const _unavailable = StudioFailure(
    code: StudioFailureCode.unavailable,
    message: 'The current complete AgentDirectory is not available; partial members are not authoritative.',
    retryable: true,
    correlationId: 'agent-directory-members',
  );
}
