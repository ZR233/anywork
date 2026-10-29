import '../../../models.dart';
import 'conversation_watermark.dart';
import '../../studio/stores/domain_sync.dart';

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
  StudioTurnView? get lastTurn => workspace?.lastTurn;

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
