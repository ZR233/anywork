import '../../models.dart';

/// Agent membership comes from the complete AgentDirectory, never a Thread page.
/// Known directory rows may complete a session identity, but Native thread
/// snapshots never decide membership.
abstract final class AgentDirectoryQueries {
  /// 目录身份判据：优先智能体目录行的 `sessionId`，其次目录行自身的
  /// `sessionId`；Native Thread 快照不参与归属判定。
  static String? sessionId({
    required String? threadId,
    required List<StudioAgentView> agents,
    Iterable<SessionDirectoryRow> rows = const [],
  }) {
    if (threadId == null) return null;
    for (final agent in agents) {
      if (agent.threadId == threadId) return agent.sessionId;
    }
    for (final row in rows) {
      if (row.threadId == threadId) return row.sessionId;
    }
    return null;
  }

  /// Stable parent-first members of one session; duplicate identities never add
  /// rows and membership only reads `sessionId`/`parentAgentId`.
  static List<StudioAgentView> forSession({
    required String? sessionId,
    required List<StudioAgentView> agents,
  }) {
    if (sessionId == null) return const [];
    final members = <String, StudioAgentView>{
      for (final agent in agents)
        if (agent.sessionId == sessionId) agent.agentId: agent,
    };
    final byParent = <String?, List<StudioAgentView>>{};
    for (final agent in members.values) {
      byParent.putIfAbsent(agent.parentAgentId, () => []).add(agent);
    }
    final ordered = <StudioAgentView>[];
    final seen = <String>{};
    void append(StudioAgentView agent) {
      if (!seen.add(agent.agentId)) return;
      ordered.add(agent);
      for (final child
          in byParent[agent.agentId] ?? const <StudioAgentView>[]) {
        append(child);
      }
    }

    for (final agent in members.values) {
      if (agent.parentAgentId == null ||
          !members.containsKey(agent.parentAgentId)) {
        append(agent);
      }
    }
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
