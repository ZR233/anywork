import '../../domain/models/studio_models.dart';
import '../bridge/thread_stream_gate.dart';
import '../frb/studio_api.dart';
import 'domain_sync.dart';

/// 有界 Timeline 窗口上限。语义与旧 reducer 的 `maxTimelineWindowItems` 一致。
const int threadTimelineWindowLimit = 100;

/// 单个会话的 canonical 投影。
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

ThreadSessionState applyTimelinePageState(
  ThreadSessionState current,
  TimelinePage page,
  TimelineDirection direction, {
  bool replaceWindow = false,
  bool followBottom = false,
}) {
  final workspace = current.workspace;
  if (workspace == null || page.threadId != current.threadId) return current;
  if (_timelinePageIsStale(
    current.history,
    page,
    replaceWindow: replaceWindow,
  )) {
    return current;
  }
  final pageItems = [
    for (final item in page.items)
      if (item.threadId == current.threadId) item,
  ];
  final merged = <String, ThreadItemView>{
    if (!replaceWindow)
      for (final item in workspace.items) item.id: item,
  };
  final pagePreviewOmitted = {
    for (final preview in page.previews) preview.itemId: preview.omittedBytes,
  };
  for (final item in pageItems) {
    final existing = merged[item.id];
    final selected = existing == null
        ? item
        : _preferPageItem(
                existing,
                item,
                pageWatermark: page.watermark,
                workspaceRevision: workspace.revision,
              ) ??
              existing;
    merged[item.id] = selected.copyWith(
      bodyOmittedUnits: pagePreviewOmitted[item.id] ?? 0,
    );
  }
  final items = merged.values.toList()..sort(_compareItems);
  var latestTurn = workspace.latestTurn;
  for (final entry in page.turns) {
    latestTurn = newestSessionTurn(latestTurn, entry.turn);
  }
  final bounded = _boundedTimeline(
    workspace.copyWith(items: items, latestTurn: latestTurn),
    direction,
    anchorId: current.history.anchor?.itemId,
  );
  final droppedOlder = bounded.items.firstOrNull?.id != items.firstOrNull?.id;
  final droppedNewer = bounded.items.lastOrNull?.id != items.lastOrNull?.id;
  final history = _historyAfterPage(
    current.history,
    page,
    bounded: bounded,
    direction: direction,
    replaceWindow: replaceWindow,
    followBottom: followBottom,
    droppedOlder: droppedOlder,
    droppedNewer: droppedNewer,
  );
  return current.copyWith(
    workspace: bounded,
    history: _syncItemBody(history, bounded),
  );
}

ThreadSessionState applyChatSnapshotState(
  ThreadSessionState current,
  StudioChatSnapshot snapshot,
) {
  final workspace = current.workspace;
  if (workspace == null) return current;
  if (current.hasChatWindow &&
      current.chatVersion != null &&
      snapshot.version < current.chatVersion!) {
    return current;
  }
  final items = [for (final entry in snapshot.items) entry.item];
  final next = workspace.copyWith(items: items);
  return current.copyWith(
    workspace: next,
    chatVersion: snapshot.version,
    hasChatWindow: true,
    history: _syncItemBody(
      current.history.copyWith(
        hasOlder: snapshot.hasOlder,
        hasNewer: snapshot.hasNewer,
        canExtendLatest: snapshot.canExtendLatest,
        isLoading: false,
      ),
      next,
    ),
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
  final workspace = current.workspace;
  if (workspace == null) return current;
  return current.copyWith(
    workspace: workspace.copyWith(items: const []),
    history: ThreadHistoryWindow(
      epoch: current.history.epoch + 1,
      databaseId: current.history.databaseId,
      appliedWriteSequence: current.history.appliedWriteSequence,
    ),
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

bool _timelinePageIsStale(
  ThreadHistoryWindow window,
  TimelinePage page, {
  required bool replaceWindow,
}) {
  final windowDatabase = window.databaseId;
  final pageDatabase = page.databaseId;
  final identityKnown = windowDatabase.isNotEmpty && pageDatabase.isNotEmpty;
  if (identityKnown && windowDatabase != pageDatabase) return !replaceWindow;
  if (identityKnown &&
      !replaceWindow &&
      page.watermark < window.appliedWriteSequence) {
    return true;
  }
  return false;
}

ThreadItemView? _preferPageItem(
  ThreadItemView existing,
  ThreadItemView incoming, {
  required int pageWatermark,
  required int workspaceRevision,
}) {
  if (!_sameItemIdentity(existing, incoming)) return null;
  if (incoming.revision < existing.revision) return null;
  final stable = incoming.ordinal == existing.ordinal
      ? incoming
      : incoming.copyWith(ordinal: existing.ordinal);
  if (stable.revision > existing.revision) return stable;
  if (stable.isTerminal && !existing.isTerminal) return stable;
  if (pageWatermark >= workspaceRevision &&
      stable.contextDisposition != existing.contextDisposition) {
    return existing.copyWith(contextDisposition: stable.contextDisposition);
  }
  return null;
}

bool _sameItemIdentity(ThreadItemView left, ThreadItemView right) {
  return left.id == right.id &&
      left.threadId == right.threadId &&
      left.turnId == right.turnId &&
      left.kind == right.kind;
}

int _compareItems(ThreadItemView left, ThreadItemView right) {
  final ordinal = left.ordinal.compareTo(right.ordinal);
  return ordinal != 0 ? ordinal : left.id.compareTo(right.id);
}

ThreadWorkspace _boundedTimeline(
  ThreadWorkspace workspace,
  TimelineDirection direction, {
  String? anchorId,
}) {
  final all = workspace.items;
  var start =
      all.length <= threadTimelineWindowLimit ||
          direction == TimelineDirection.older
      ? 0
      : all.length - threadTimelineWindowLimit;
  final anchor = all.indexWhere((item) => item.id == anchorId);
  if (anchor >= 0) {
    if (anchor < start) start = anchor;
    if (anchor >= start + threadTimelineWindowLimit) {
      start = anchor - threadTimelineWindowLimit + 1;
    }
  }
  final items = all.sublist(
    start,
    (start + threadTimelineWindowLimit).clamp(start, all.length),
  );
  return workspace.copyWith(items: items);
}

ThreadHistoryWindow _historyAfterPage(
  ThreadHistoryWindow history,
  TimelinePage page, {
  required ThreadWorkspace bounded,
  required TimelineDirection direction,
  required bool replaceWindow,
  required bool followBottom,
  required bool droppedOlder,
  required bool droppedNewer,
}) {
  final databaseId = page.databaseId.isEmpty
      ? history.databaseId
      : page.databaseId;
  final appliedWriteSequence = replaceWindow
      ? page.watermark
      : (page.watermark > history.appliedWriteSequence
            ? page.watermark
            : history.appliedWriteSequence);
  final followHasOlder = droppedOlder || page.olderCursor != null;
  final followOlderCursor = !followHasOlder
      ? null
      : droppedOlder
      ? bounded.items.firstOrNull?.id
      : page.olderCursor ?? bounded.items.firstOrNull?.id;
  return history.copyWith(
    olderCursor: followBottom
        ? followOlderCursor
        : droppedOlder
        ? bounded.items.firstOrNull?.id
        : (replaceWindow || direction == TimelineDirection.older)
        ? page.olderCursor
        : history.olderCursor,
    newerCursor: followBottom
        ? null
        : droppedNewer
        ? bounded.items.lastOrNull?.id
        : (replaceWindow || direction == TimelineDirection.newer)
        ? page.newerCursor
        : history.newerCursor,
    hasOlder: followBottom
        ? followHasOlder
        : droppedOlder ||
              ((replaceWindow || direction == TimelineDirection.older)
                  ? page.olderCursor != null
                  : history.hasOlder),
    hasNewer: followBottom
        ? droppedNewer
        : droppedNewer ||
              ((replaceWindow || direction == TimelineDirection.newer)
                  ? page.newerCursor != null
                  : history.hasNewer),
    detached: followBottom
        ? false
        : replaceWindow ||
              history.detached ||
              (bounded.items.length < page.items.length &&
                  direction == TimelineDirection.older),
    isLoading: false,
    errorMessage:
        followBottom || replaceWindow || direction == TimelineDirection.older
        ? null
        : history.errorMessage,
    newerError:
        followBottom || replaceWindow || direction == TimelineDirection.newer
        ? null
        : history.newerError,
    databaseId: databaseId,
    appliedWriteSequence: appliedWriteSequence,
  );
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
      window.olderCursor != null ||
      window.newerCursor != null ||
      window.errorMessage != null ||
      window.newerError != null ||
      window.databaseId.isNotEmpty ||
      window.appliedWriteSequence != 0 ||
      window.previewedItemIds.isNotEmpty ||
      window.loadingItemIds.isNotEmpty ||
      window.pendingItemBodyIds.isNotEmpty ||
      window.itemBodyErrors.isNotEmpty ||
      window.unavailableItemIds.isNotEmpty;
}
