import '../../models.dart';
import 'thread_stream_gate.dart';
import '../../studio_ports.dart';
import 'stores/domain_sync.dart';

/// 单个会话的 canonical 状态投影。
///
/// 这里只有 Thread 状态事实（runtime/turn/interactions/storage 与流水位）。正文、已加载消息、
/// 展示模式与分页游标都不属于它：唯一已加载消息集合由当前展示 lease 的
/// `InMemoryChatController` 持有，内容连接另由 SDK 的有界尾部 reducer 负责
/// （design/25 §25.6、design/26 §26.8）。状态流不反写正文，正文恢复也不把状态标成 ready。
///
/// revision / streamEpoch / baseRevision 都参与相等。
/// workflow 在 [runtime] 上，不另建旁路字段。
class ThreadSessionState {
  const ThreadSessionState({
    required this.threadId,
    this.workspace,
    this.hasSnapshot = false,
    this.streamEpoch,
    this.baseRevision,
    this.sync = const DomainSyncStatus(),
  });

  final String threadId;
  final ThreadWorkspace? workspace;
  final bool hasSnapshot;
  final int? streamEpoch;
  final int? baseRevision;
  final DomainSyncStatus sync;

  int get revision => workspace?.revision ?? 0;
  ThreadRuntimeView? get runtime => workspace?.runtime;
  WorkflowRuntimeView? get workflow => runtime?.workflow;
  StudioTurnView? get activeTurn => workspace?.activeTurn;
  List<PendingInteraction> get interactions =>
      workspace?.interactions ?? const [];
  ThreadActivityView? get activity => workspace?.activity;
  ThreadStorageStateView? get storage => workspace?.storage;

  ThreadStreamWatermark get watermark => ThreadStreamWatermark(
    hasSnapshot: hasSnapshot,
    revision: revision,
    epoch: streamEpoch,
    baseRevision: baseRevision,
  );

  ThreadSessionState copyWith({
    ThreadWorkspace? workspace,
    bool clearWorkspace = false,
    bool? hasSnapshot,
    Object? streamEpoch = _unset,
    Object? baseRevision = _unset,
    DomainSyncStatus? sync,
  }) {
    return ThreadSessionState(
      threadId: threadId,
      workspace: clearWorkspace ? null : workspace ?? this.workspace,
      hasSnapshot: hasSnapshot ?? this.hasSnapshot,
      streamEpoch: identical(streamEpoch, _unset)
          ? this.streamEpoch
          : streamEpoch as int?,
      baseRevision: identical(baseRevision, _unset)
          ? this.baseRevision
          : baseRevision as int?,
      sync: sync ?? this.sync,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ThreadSessionState &&
          threadId == other.threadId &&
          hasSnapshot == other.hasSnapshot &&
          revision == other.revision &&
          streamEpoch == other.streamEpoch &&
          baseRevision == other.baseRevision &&
          sync == other.sync &&
          identical(workspace, other.workspace);

  @override
  int get hashCode => Object.hash(
    threadId,
    hasSnapshot,
    revision,
    streamEpoch,
    baseRevision,
    sync,
    identityHashCode(workspace),
  );
}

const Object _unset = Object();

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
    latestTurn: newestSessionTurn(base.latestTurn, snapshot.activeTurn),
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

StudioTurnView? newestSessionTurn(StudioTurnView? left, StudioTurnView? right) {
  if (left == null) return right;
  if (right == null) return left;
  if (left.turnId == right.turnId) {
    if (right.revision == left.revision) {
      return right.state.isBusy && left.state.isTerminal ? left : right;
    }
    return right.revision > left.revision ? right : left;
  }
  final timeOrder = right.updatedAt.compareTo(left.updatedAt);
  return timeOrder > 0 || (timeOrder == 0 && right.revision > left.revision)
      ? right
      : left;
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
