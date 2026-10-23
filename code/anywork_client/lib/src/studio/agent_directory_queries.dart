import '../../models.dart';

/// Agent membership comes from the complete AgentDirectory, never a Thread page.
/// Known Thread facts may complete a root identity, but cannot create members.
abstract final class AgentDirectoryQueries {
  static String? rootThreadId({
    required String? threadId,
    required List<StudioAgentView> agents,
    Iterable<StudioThread> threads = const [],
  }) => _AgentDirectoryIndex(agents, threads).rootOf(threadId);

  /// Stable parent-first members; duplicate Thread identities never add rows.
  static List<StudioAgentView> forRoot({
    required String? rootThreadId,
    required List<StudioAgentView> agents,
    Iterable<StudioThread> threads = const [],
  }) {
    if (rootThreadId == null) return const [];
    final index = _AgentDirectoryIndex(agents, threads);
    final members = <String, StudioAgentView>{};
    for (final agent in index.byThread.values) {
      if (index.rootOf(agent.threadId) == rootThreadId) {
        members[agent.threadId] = agent;
      }
    }
    final byParent = <String?, List<StudioAgentView>>{};
    for (final agent in members.values) {
      byParent.putIfAbsent(agent.parentPath, () => []).add(agent);
    }
    final ordered = <StudioAgentView>[];
    final seen = <String>{};
    void append(StudioAgentView agent) {
      if (!seen.add(agent.threadId)) return;
      ordered.add(agent);
      for (final child in byParent[agent.path] ?? const <StudioAgentView>[]) {
        append(child);
      }
    }

    final root = members[rootThreadId];
    if (root != null) append(root);
    for (final agent in members.values) {
      append(agent);
    }
    return ordered;
  }

  /// Status groups retain the canonical parent/sibling order within each group.
  static List<StudioAgentView> menuOrder(List<StudioAgentView> agents) {
    final indexed = [
      for (var index = 0; index < agents.length; index++)
        (index, agents[index]),
    ];
    indexed.sort((left, right) {
      final status = _statusPriority(left.$2.state)
          .compareTo(_statusPriority(right.$2.state));
      return status == 0 ? left.$1.compareTo(right.$1) : status;
    });
    return [for (final entry in indexed) entry.$2];
  }

  static int _statusPriority(StudioAgentState state) => switch (state) {
    QueuedStudioAgent() ||
    RunningStudioAgent() ||
    WaitingToolStudioAgent() ||
    WaitingInteractionStudioAgent() ||
    CancellingStudioAgent() => 0,
    FaultedStudioAgent() => 1,
    IdleStudioAgent() => 2,
    ClosingStudioAgent() || ClosedStudioAgent() => 3,
  };
}

/// One local index per query, not a retained membership cache. Canonical order
/// wins duplicate identities and exact parent links are never parsed as paths.
final class _AgentDirectoryIndex {
  _AgentDirectoryIndex(
    List<StudioAgentView> agents,
    Iterable<StudioThread> threads,
  ) {
    for (final agent in agents) {
      if (byThread.containsKey(agent.threadId)) continue;
      byThread[agent.threadId] = agent;
      _byPath.putIfAbsent(agent.path, () => agent);
    }
    for (final thread in threads) {
      _threads.putIfAbsent(thread.id, () => thread);
    }
  }

  final byThread = <String, StudioAgentView>{};
  final _byPath = <String, StudioAgentView>{};
  final _threads = <String, StudioThread>{};

  String? rootOf(String? threadId) {
    if (threadId == null) return null;
    var current = byThread[threadId];
    final visited = <String>{};
    while (current != null && visited.add(current.threadId)) {
      final savedRoot = current.rootThreadId;
      if (savedRoot != null && savedRoot.isNotEmpty) return savedRoot;
      final parent = current.parentPath;
      if (parent == null && current.depth == 0) return current.threadId;
      current = parent == null ? null : _byPath[parent];
    }
    return _threads[threadId]?.effectiveRootThreadId;
  }
}
