import '../../../models.dart';
import '../../../studio_ports.dart';
import '../domain/conversation_state.dart';
import 'thread_stream_gate.dart';

/// 快照替换当前状态事实；正文与展示不属于这里。新订阅代次允许 revision 回退。
ThreadSessionState applyThreadSnapshotState(
  ThreadSessionState current,
  ThreadWorkspace snapshot, {
  StudioThread? directoryThread,
}) {
  if (snapshot.thread.id.isEmpty || snapshot.thread.id != current.threadId) {
    return current;
  }
  final previous = current.workspace;
  final base = previous ?? snapshot;
  final next = base.copyWith(
    thread: directoryThread ?? snapshot.thread,
    revision: snapshot.revision,
    activeTurn: snapshot.activeTurn,
    interactions: snapshot.interactions,
    runtime: snapshot.runtime,
    todo: snapshot.todo,
    activity: snapshot.activity,
    storage: snapshot.storage,
    // choose 不是结合运算：必须按 latest → snapshot.latest → snapshot.active
    // 的固定左结合次序折叠，右折叠会让同身份 terminal 候选提前挡掉更高的
    // active revision（A terminal 5 → B latest 6 → A active 7 末态应为 A 7）。
    latestTurn: newestSessionTurn(
      newestSessionTurn(base.latestTurn, snapshot.latestTurn),
      snapshot.activeTurn,
    ),
  );
  return current.copyWith(
    workspace: next,
    hasSnapshot: true,
    baseRevision: snapshot.revision,
    sync: current.sync.connected(),
  );
}

/// 通知必须通过 [classifyThreadFrame]；这里再按水位兜底。
ThreadSessionState applyThreadNotificationState(
  ThreadSessionState current,
  ThreadNotificationFrame frame,
) {
  if (frame.threadId != current.threadId) return current;
  if (classifyThreadFrame(current.watermark, frame) !=
      ThreadFrameDecision.apply) {
    return current;
  }
  final workspace = current.workspace;
  if (workspace == null) return current;
  final updated = switch (frame.update) {
    ThreadTurnUpdate(:final turn) => _applyTurn(
      workspace,
      frame.revision,
      turn,
    ),
    ThreadActivityUpdate(:final activity) => _applyActivity(
      workspace,
      frame.revision,
      activity,
    ),
    ThreadInteractionUpdate(:final interaction, :final pending) =>
      _applyInteraction(workspace, frame.revision, interaction, pending),
    ThreadRuntimeUpdate(:final runtime, :final todo) => workspace.copyWith(
      revision: frame.revision,
      runtime: runtime,
      todo: todo,
    ),
    ThreadStorageUpdate(:final storage) => workspace.copyWith(
      revision: frame.revision,
      storage: storage,
    ),
  };
  return current.copyWith(
    workspace: updated,
    streamEpoch: frame.epoch ?? current.streamEpoch,
    baseRevision: frame.baseRevision ?? frame.revision - 1,
    sync: current.sync.connected(),
  );
}

ThreadWorkspace _applyTurn(
  ThreadWorkspace workspace,
  int revision,
  StudioTurnView turn,
) {
  final observed = workspace.latestTurn;
  if (observed != null &&
      observed.turnId == turn.turnId &&
      observed.state.isTerminal &&
      turn.state.isBusy) {
    return workspace.copyWith(revision: revision);
  }
  final active = workspace.activeTurn;
  return workspace.copyWith(
    revision: revision,
    activeTurn: turn.state.isBusy
        ? turn
        : (active != null && active.turnId == turn.turnId ? null : active),
    latestTurn: newestSessionTurn(observed, turn),
  );
}

ThreadWorkspace _applyActivity(
  ThreadWorkspace workspace,
  int revision,
  ThreadActivityView? activity,
) {
  if (activity == null) {
    return workspace.copyWith(revision: revision, activity: null);
  }
  final existing = workspace.activity;
  if (existing != null &&
      existing.identity == activity.identity &&
      activity.revision < existing.revision) {
    return workspace.copyWith(revision: revision);
  }
  return workspace.copyWith(revision: revision, activity: activity);
}

ThreadWorkspace _applyInteraction(
  ThreadWorkspace workspace,
  int revision,
  PendingInteraction interaction,
  bool pending,
) {
  final interactions = [...workspace.interactions];
  final index = interactions.indexWhere((item) => item.id == interaction.id);
  if (!pending) {
    if (index >= 0) interactions.removeAt(index);
  } else if (index >= 0) {
    interactions[index] = interaction;
  } else {
    interactions.add(interaction);
  }
  return workspace.copyWith(revision: revision, interactions: interactions);
}
