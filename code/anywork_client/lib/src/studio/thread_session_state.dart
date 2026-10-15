import '../../models.dart';
import 'thread_stream_gate.dart';
import '../../studio_ports.dart';
import 'stores/domain_sync.dart';

/// 单个会话的 canonical 投影。
///
/// `workspace.items` 是权威 ChatView 窗口的**只读显示镜像**：窗口顺序、有界与去重都由原生
/// owner 保证，本地不再做第二份排序/裁剪/去重；唯一写入者是 [`applyChatFrameState`]（Reset/Patch
/// reducer）。`thread projection`（runtime/turn/interactions）来自 Thread 有序流，两路事实互相独立。
///
/// revision / streamEpoch / baseRevision / history.epoch 都参与相等。
/// workflow 在 [runtime] 上，不另建旁路字段。
class ThreadSessionState {
  const ThreadSessionState({
    required this.threadId,
    this.workspace,
    this.hasSnapshot = false,
    this.streamEpoch,
    this.baseRevision,
    this.history = const ThreadHistoryWindow(),
    this.chatVersion,
    this.chatViewId,
    this.hasChatWindow = false,
    this.sync = const DomainSyncStatus(),
  });

  final String threadId;
  final ThreadWorkspace? workspace;
  final bool hasSnapshot;
  final int? streamEpoch;
  final int? baseRevision;
  final ThreadHistoryWindow history;
  final int? chatVersion;

  /// Application-owned binding identity, separate from native content version.
  final String? chatViewId;
  final bool hasChatWindow;
  final DomainSyncStatus sync;

  int get revision => workspace?.revision ?? 0;
  ThreadRuntimeView? get runtime => workspace?.runtime;
  WorkflowRuntimeView? get workflow => runtime?.workflow;
  StudioTurnView? get activeTurn => workspace?.activeTurn;
  List<PendingInteraction> get interactions =>
      workspace?.interactions ?? const [];
  ThreadActivityView? get activity => workspace?.activity;
  ThreadStorageStateView? get storage => workspace?.storage;
  List<ThreadItemView> get items => workspace?.items ?? const [];

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
    ThreadHistoryWindow? history,
    Object? chatVersion = _unset,
    Object? chatViewId = _unset,
    bool? hasChatWindow,
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
      history: history ?? this.history,
      chatVersion: identical(chatVersion, _unset)
          ? this.chatVersion
          : chatVersion as int?,
      chatViewId: identical(chatViewId, _unset)
          ? this.chatViewId
          : chatViewId as String?,
      hasChatWindow: hasChatWindow ?? this.hasChatWindow,
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
          history == other.history &&
          chatVersion == other.chatVersion &&
          chatViewId == other.chatViewId &&
          hasChatWindow == other.hasChatWindow &&
          sync == other.sync &&
          identical(workspace, other.workspace);

  @override
  int get hashCode => Object.hash(
    threadId,
    hasSnapshot,
    revision,
    streamEpoch,
    baseRevision,
    history,
    chatVersion,
    chatViewId,
    hasChatWindow,
    sync,
    identityHashCode(workspace),
  );
}

const Object _unset = Object();

/// 快照替换当前状态事实，但保留已有阅读窗口。新订阅代次允许 revision 回退。
ThreadSessionState applyThreadSnapshotState(
  ThreadSessionState current,
  ThreadWorkspace snapshot, {
  StudioThread? directoryThread,
}) {
  if (snapshot.thread.id.isEmpty || snapshot.thread.id != current.threadId) {
    return current;
  }
  final previous = current.workspace;
  final base = previous ?? snapshot.copyWith(items: const []);
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
    history: _syncItemBody(current.history, updated),
    sync: current.sync.connected(),
  );
}

/// 一帧权威内容的本地应用结果。
enum ChatFrameOutcome {
  /// 帧已应用（或幂等空帧），read model 前进。
  applied,

  /// 帧属于旧绑定/已交付版本，静默丢弃。
  irrelevant,

  /// 连续性缺口或字段提交不匹配：废弃当前绑定并重新打开同一会话的有界窗口。
  resync,
}

/// 帧未被应用时的具体判定依据。
///
/// 观测记录（[ChatViewEvents]）需要能回答「哪条校验失败」，因此拒绝路径不允许只返回一个
/// 笼统的 outcome：`irrelevant` 与 `resync` 都必须带上命中的分支。
enum ChatFrameRejectReason {
  /// 帧已应用，没有拒绝。
  none,

  /// store 尚未建立 workspace 快照，无法判定归属。
  noWorkspace,

  /// Reset 版本早于已交付版本。
  resetOlderThanDelivered,

  /// 尚未交付任何窗口，Patch 没有可校验的基线。
  patchWithoutBaseline,

  /// `patch.from` 既不等于本地版本、也不早于本地版本：无法判定是重复还是缺口。
  patchFromMismatch,

  /// `patch.from` 早于本地版本且 `to` 更小：属于已交付范围。
  patchAlreadyDelivered,

  /// `patch.from` 早于本地版本但 `to` 更大：中间帧缺失。
  patchGap,

  /// Patch 版本非递增（`to <= from`）。
  patchNonIncreasing,

  /// Patch 的 splice 越界或空操作。
  spliceOutOfRange,

  /// Patch 引用了当前窗口不存在的 item。
  itemNotInWindow,

  /// item 提交的字段与本地 revision/终态不匹配。
  itemCommitMismatch,
}

/// 帧应用的返回：`state` 恒为「应用后的最新状态」（`applied`/`irrelevant` 时可能等于输入）。
class ChatFrameResult {
  const ChatFrameResult(
    this.state,
    this.outcome, [
    this.reason = ChatFrameRejectReason.none,
  ]);

  final ThreadSessionState state;
  final ChatFrameOutcome outcome;

  /// 拒绝依据；`applied` 时为 [ChatFrameRejectReason.none]。
  final ChatFrameRejectReason reason;
}

/// 唯一 chat reducer：接收权威 ChatView 交付的 Reset/Patch 帧。
///
/// Patch 仅在 `from == 本地 chatVersion` 时应用；`to` 必须更大但无需恰好加一（允许合并跨版本）。
/// 已交付版本的重复帧幂等丢弃；缺口、目标 item 不在窗口、或 `expectedRevision` 不匹配都按
/// `resync` 收束——由 binding 重开窗口拿最新有界 Reset，不在本地拼接或修补。
ChatFrameResult applyChatFrameState(
  ThreadSessionState current,
  StudioChatFrame frame,
) {
  final workspace = current.workspace;
  if (workspace == null) {
    return ChatFrameResult(
      current,
      ChatFrameOutcome.irrelevant,
      ChatFrameRejectReason.noWorkspace,
    );
  }
  return switch (frame) {
    StudioChatReset(:final snapshot) => _applyReset(
      current,
      workspace,
      snapshot,
    ),
    StudioChatPatch() => _applyPatch(current, workspace, frame),
  };
}

ChatFrameResult _applyReset(
  ThreadSessionState current,
  ThreadWorkspace workspace,
  StudioChatSnapshot snapshot,
) {
  final version = current.chatVersion;
  if (current.hasChatWindow && version != null && snapshot.version < version) {
    return ChatFrameResult(
      current,
      ChatFrameOutcome.irrelevant,
      ChatFrameRejectReason.resetOlderThanDelivered,
    );
  }
  final items = [for (final entry in snapshot.items) entry.item];
  final next = workspace.copyWith(items: items);
  // Content focus describes the server window. Reading intent and pixel offset
  // belong to the Client and survive a new view's initial latest Reset, even
  // when its saved row needs a subsequent focus control to enter the window.
  final history = current.history.copyWith(
    hasOlder: snapshot.hasOlder,
    hasNewer: snapshot.hasNewer,
    canExtendLatest: snapshot.canExtendLatest,
    olderCursor: items.firstOrNull?.id,
    newerCursor: items.lastOrNull?.id,
  );
  return ChatFrameResult(
    current.copyWith(
      workspace: next,
      chatVersion: snapshot.version,
      hasChatWindow: true,
      history: _syncItemBody(history, next),
    ),
    ChatFrameOutcome.applied,
  );
}

ChatFrameResult _applyPatch(
  ThreadSessionState current,
  ThreadWorkspace workspace,
  StudioChatPatch patch,
) {
  final version = current.chatVersion;
  if (version == null || !current.hasChatWindow) {
    return ChatFrameResult(
      current,
      ChatFrameOutcome.resync,
      ChatFrameRejectReason.patchWithoutBaseline,
    );
  }
  if (patch.from != version) {
    final reason = patch.to <= version
        ? ChatFrameRejectReason.patchAlreadyDelivered
        : patch.from < version
        ? ChatFrameRejectReason.patchGap
        : ChatFrameRejectReason.patchFromMismatch;
    return ChatFrameResult(
      current,
      patch.to <= version
          ? ChatFrameOutcome.irrelevant
          : ChatFrameOutcome.resync,
      reason,
    );
  }
  if (patch.to <= patch.from) {
    return ChatFrameResult(
      current,
      ChatFrameOutcome.resync,
      ChatFrameRejectReason.patchNonIncreasing,
    );
  }
  var visible = [...workspace.items];
  for (final change in patch.changes) {
    switch (change) {
      case StudioViewSplice(:final index, :final remove, :final items):
        if (index < 0 ||
            remove < 0 ||
            index + remove > visible.length ||
            remove == 0 && items.isEmpty) {
          return ChatFrameResult(
            current,
            ChatFrameOutcome.resync,
            ChatFrameRejectReason.spliceOutOfRange,
          );
        }
        visible.replaceRange(index, index + remove, [
          for (final entry in items) entry.item,
        ]);
      case StudioViewItemUpdate(
        :final itemId,
        :final expectedRevision,
        :final revision,
        :final omittedUnits,
        :final saved,
        :final fields,
      ):
        // 整组字段在**一次**提交里原子应用：本地 revision 必须等于 expectedRevision，
        // 应用完再一次性提交 revision/omitted/saved。终态条目拒绝迟到流式字段，
        // 只接受保存/版本帧；任一条不成立就重开权威窗口，绝不把片段当正文。
        // 字段身份只由 typed discriminator 决定（如 thinkingContent 的 chunkIndex），
        // 不解析 JSON、不按字符串形状推断。
        final index = visible.indexWhere((item) => item.id == itemId);
        if (index < 0) {
          return ChatFrameResult(
            current,
            ChatFrameOutcome.resync,
            ChatFrameRejectReason.itemNotInWindow,
          );
        }
        final nextItem = visible[index].applyFieldUpdates(
          fields: [
            for (final update in fields)
              ThreadFieldUpdateView(field: update.field, change: update.change),
          ],
          expectedRevision: expectedRevision,
          revision: revision,
          omittedUnits: omittedUnits,
          saved: saved,
          terminal: visible[index].executionTerminal,
        );
        if (nextItem == null) {
          return ChatFrameResult(
            current,
            ChatFrameOutcome.resync,
            ChatFrameRejectReason.itemCommitMismatch,
          );
        }
        visible[index] = nextItem;
    }
  }
  final next = workspace.copyWith(items: List.unmodifiable(visible));
  final history = current.history.copyWith(
    hasNewer: patch.hasNewer,
    olderCursor: visible.firstOrNull?.id,
    newerCursor: visible.lastOrNull?.id,
  );
  return ChatFrameResult(
    current.copyWith(
      workspace: next,
      chatVersion: patch.to,
      history: _syncItemBody(history, next),
    ),
    ChatFrameOutcome.applied,
  );
}

ThreadSessionState releaseThreadHistoryState(ThreadSessionState current) {
  final workspace = current.workspace;
  if (workspace == null) return current;
  final alreadyEmpty =
      workspace.items.isEmpty && !_historyTouched(current.history);
  if (alreadyEmpty) return current;
  return current.copyWith(
    workspace: workspace.copyWith(items: const []),
    history: ThreadHistoryWindow(
      anchor: current.history.anchor,
      detached: current.history.detached,
      epoch: current.history.epoch + 1,
    ),
  );
}

ThreadSessionState jumpTimelineToLatestState(ThreadSessionState current) {
  // 跳回最新是阅读意图切换：本地只推进 epoch 失效旧锚点恢复，正文镜像保留，
  // 由权威窗口的 focus(latest) 交付的 Reset 替换，不渲染中间空窗。
  final history = ThreadHistoryWindow(epoch: current.history.epoch + 1);
  if (history == current.history) return current;
  return current.copyWith(history: history);
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

ThreadHistoryWindow _syncItemBody(
  ThreadHistoryWindow history,
  ThreadWorkspace workspace,
) {
  final previewed = {
    for (final item in workspace.items)
      if (item.bodyPreviewed) item.id,
  };
  final loading = history.loadingItemIds.where(previewed.contains).toSet();
  final pending = history.pendingItemBodyIds.where(previewed.contains).toSet();
  final errors = {
    for (final entry in history.itemBodyErrors.entries)
      if (previewed.contains(entry.key)) entry.key: entry.value,
  };
  final unavailable = history.unavailableItemIds
      .where(previewed.contains)
      .toSet();
  if (_sameIds(previewed, history.previewedItemIds) &&
      _sameIds(loading, history.loadingItemIds) &&
      _sameIds(pending, history.pendingItemBodyIds) &&
      _sameIds(unavailable, history.unavailableItemIds) &&
      errors.length == history.itemBodyErrors.length) {
    return history;
  }
  return history.copyWith(
    previewedItemIds: previewed,
    loadingItemIds: loading,
    itemBodyErrors: errors,
    pendingItemBodyIds: pending,
    unavailableItemIds: unavailable,
  );
}

bool _sameIds(Set<String> left, Set<String> right) =>
    left.length == right.length && left.containsAll(right);

bool _historyTouched(ThreadHistoryWindow window) {
  return window.hasOlder ||
      window.hasNewer ||
      window.canExtendLatest ||
      window.olderCursor != null ||
      window.newerCursor != null ||
      window.errorMessage != null ||
      window.newerError != null ||
      window.previewedItemIds.isNotEmpty ||
      window.loadingItemIds.isNotEmpty ||
      window.pendingItemBodyIds.isNotEmpty ||
      window.itemBodyErrors.isNotEmpty ||
      window.unavailableItemIds.isNotEmpty;
}

/// 写入阅读锚点：浏览历史意图标记脱离底部（对齐旧 updateTimelineAnchor 语义）。
ThreadSessionState setTimelineAnchorState(
  ThreadSessionState state,
  TimelineAnchor anchor,
) {
  final history = state.history.copyWith(
    anchor: anchor,
    detached: anchor.readingIntent == TimelineReadingIntent.browseHistory,
  );
  if (history == state.history) return state;
  return state.copyWith(history: history);
}

/// 一条按身份的正文补齐开始：清旧错误与不可回源标记。
ThreadSessionState beginItemBodyLoadState(
  ThreadSessionState state,
  String itemId,
) {
  final history = state.history;
  if (!history.previewedItemIds.contains(itemId) ||
      history.loadingItemIds.contains(itemId)) {
    return state;
  }
  final next = history.copyWith(
    loadingItemIds: {...history.loadingItemIds, itemId},
    itemBodyErrors: Map<String, String>.from(history.itemBodyErrors)
      ..remove(itemId),
    unavailableItemIds: {...history.unavailableItemIds}..remove(itemId),
  );
  return state.copyWith(history: next);
}

/// 补齐已发出但此刻取不到完整正文：保留预览与重试入口，不下不可回源结论。
ThreadSessionState markItemBodyPendingState(
  ThreadSessionState state,
  String itemId,
) {
  final current = state.history;
  final history = current.copyWith(
    loadingItemIds: {...current.loadingItemIds}..remove(itemId),
    pendingItemBodyIds: {...current.pendingItemBodyIds, itemId},
  );
  return state.copyWith(history: history);
}

/// 补齐失败：保留预览并记录 typed 错误，等待下一次可见触发或显式重试。
ThreadSessionState failItemBodyLoadState(
  ThreadSessionState state,
  String itemId,
  String message,
) {
  final current = state.history;
  final history = current.copyWith(
    loadingItemIds: {...current.loadingItemIds}..remove(itemId),
    itemBodyErrors: {...current.itemBodyErrors, itemId: message},
    pendingItemBodyIds: {...current.pendingItemBodyIds}..remove(itemId),
  );
  return state.copyWith(history: history);
}
