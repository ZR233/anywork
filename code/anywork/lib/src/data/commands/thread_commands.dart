import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../domain/models/studio_models.dart';
import '../frb/studio_api.dart';
import '../repositories/studio_api_provider.dart';
import '../stores/domain_sync.dart';
import '../stores/recovery_store.dart';
import '../stores/selection_store.dart';
import '../stores/settings_store.dart';
import '../stores/snapshot_fanout.dart';
import '../stores/thread_directory_store.dart';
import '../stores/thread_session_store.dart';
import '../stores/thread_session_state.dart';
import 'command_lane.dart';
import 'settings_commands.dart';

part 'thread_commands.g.dart';

/// 会话命令 lane。
///
/// route 更新与设置写入共用 settings lane，并按双 revision rebase。响应里的
/// runtime 不是第二事实源：只合并 settings，route 本身等 Thread 有序流。
/// 其他命令直通数据源；无目录 revision 的结果不拼进目录。
@Riverpod(keepAlive: true)
class ThreadCommands extends _$ThreadCommands {
  final CommandLane _lane = CommandLane();
  final Set<String> _historyInFlight = <String>{};

  @override
  ThreadCommandBoard build() => const ThreadCommandBoard();

  Future<void> setThreadModelRoute({
    String? threadId,
    required String providerId,
    required String model,
    String? effort,
  }) {
    final targetThreadId =
        threadId ?? ref.read(selectionStoreProvider).selectedThreadId;
    if (targetThreadId == null) return Future<void>.value();
    return ref
        .read(settingsCommandsProvider.notifier)
        .enqueueSettingsWrite(
          () => _applyThreadModelRoute(
            threadId: targetThreadId,
            providerId: providerId,
            model: model,
            effort: effort,
          ),
        );
  }

  Future<void> setThreadMode(ThreadModeId mode) {
    return _lane.enqueue(() async {
      final threadId = ref.read(selectionStoreProvider).selectedThreadId;
      if (threadId == null) return;
      final thread = _directoryThread(threadId);
      final runtime = ref.read(threadSessionStoreProvider(threadId)).runtime;
      if (thread == null ||
          !thread.isRoot ||
          thread.mode == mode ||
          thread.status != ThreadStatusView.idle ||
          (runtime?.hasActiveWorkflow ?? false) ||
          _blocksThread(threadId)) {
        return;
      }
      await _api.setThreadMode(threadId: threadId, mode: mode);
      if (!ref.mounted) return;
      await _reloadProduct();
      await _refreshSession(threadId);
    });
  }

  /// 草稿仍属于后续 route 层。这里只接受已经组装好的输入，不写 composer canonical。
  Future<void> submitComposer(String threadId, StudioPromptInput input) {
    return _lane.enqueue(() async {
      if (input.text.trim().isEmpty && input.attachmentDraftIds.isEmpty) {
        return;
      }
      if (_blocksThread(threadId)) return;
      final key = 'submit:$threadId';
      _begin(key, label: threadId);
      try {
        await _api.submitPrompt(threadId, input);
        _clear(key);
      } catch (error) {
        _fail(key, threadId, error);
        rethrow;
      }
    });
  }

  /// 解析当前会话的 pending interaction。
  ///
  /// 响应只确认命令；canonical interaction 帧仅由 Thread 有序流写入，
  /// 不在本地删除或改写 interaction（design/25 §25.5）。
  Future<void> resolveActiveInteraction(
    String threadId,
    String interactionId,
    InteractionResolutionCommand resolution,
  ) {
    return _lane.enqueue(() async {
      final selectedThreadId = ref
          .read(selectionStoreProvider)
          .selectedThreadId;
      final interactions = ref
          .read(threadSessionStoreProvider(threadId))
          .interactions;
      final active = [...interactions]
        ..sort(
          (left, right) =>
              interactionPriority(left.kind)
                  .compareTo(interactionPriority(right.kind)),
        );
      if (selectedThreadId != threadId ||
          active.firstOrNull?.id != interactionId) {
        final conflict = const StudioFailure(
          code: StudioFailureCode.conflict,
          message: 'The displayed interaction is no longer current',
          retryable: false,
          correlationId: 'client-interaction-conflict',
        );
        _fail('interaction:$threadId', threadId, conflict);
        throw conflict;
      }
      final key = 'interaction:$threadId';
      _begin(key, label: threadId);
      try {
        await _api.respondInteraction(interactionId, resolution);
        _clear(key);
      } catch (error) {
        _fail(key, threadId, error);
        rethrow;
      }
    });
  }

  Future<StartNewThreadResult?> submitNewThread({
    required String projectId,
    required StudioPromptInput input,
    required ThreadModeId mode,
    String? workspaceMode,
  }) {
    return _lane.enqueue(() async {
      if (input.text.trim().isEmpty && input.attachmentDraftIds.isEmpty) {
        return null;
      }
      if (_blocksProject(projectId)) return null;
      final key = 'new-thread:$projectId';
      _begin(key, label: projectId);
      try {
        final result = await _api.startNewThread(
          projectId,
          input,
          mode,
          workspaceMode: workspaceMode,
        );
        if (!ref.mounted) return result;
        await _reloadProduct();
        ref
            .read(selectionStoreProvider.notifier)
            .selectThread(projectId: projectId, threadId: result.thread.id);
        _clear(key);
        return result;
      } catch (error) {
        _fail(key, projectId, error);
        rethrow;
      }
    });
  }

  Future<void> stop(String threadId) {
    return _lane.enqueue(() async {
      if (ref.read(selectionStoreProvider).selectedThreadId != threadId) {
        return;
      }
      final turn = ref.read(threadSessionStoreProvider(threadId)).activeTurn;
      if (turn == null || !turn.state.isBusy) return;
      final key = 'stop:$threadId';
      _begin(key, label: threadId);
      try {
        await _api.interruptTurn(threadId, turn.turnId);
        _clear(key);
      } catch (error) {
        _fail(key, threadId, error);
        rethrow;
      }
    });
  }

  Future<StudioThread?> renameThread(String threadId, String title) {
    return _lane.enqueue(() async {
      final thread = _directoryThread(threadId);
      if (thread == null || !thread.isRoot || _blocksThread(threadId)) {
        return null;
      }
      final key = 'rename:$threadId';
      _begin(key, label: title);
      try {
        final renamed = await _api.renameThread(threadId, title);
        if (ref.mounted) await _reloadProduct();
        _clear(key);
        return renamed;
      } catch (error) {
        _fail(key, threadId, error);
        rethrow;
      }
    });
  }

  Future<void> archiveThread(String threadId) {
    return _lane.enqueue(() async {
      final thread = _directoryThread(threadId);
      if (thread == null || !thread.isRoot || _blocksThread(threadId)) return;
      final key = 'archive:$threadId';
      _begin(key, label: threadId);
      try {
        final result = await _api.archiveThread(threadId);
        if (!ref.mounted) return;
        for (final id in result.removedThreadIds) {
          releaseThreadSession(ref, id);
        }
        await _reloadProduct();
        final selected = ref.read(selectionStoreProvider).selectedThreadId;
        if (selected != null && result.removedThreadIds.contains(selected)) {
          ref
              .read(selectionStoreProvider.notifier)
              .replaceRemovedThread(result.nextRoot?.id);
        }
        _clear(key);
      } catch (error) {
        _fail(key, threadId, error);
        rethrow;
      }
    });
  }

  Future<void> loadOlderHistory(String threadId) =>
      _loadHistory(threadId, TimelineDirection.older);

  Future<void> loadNewerHistory(String threadId) =>
      _loadHistory(threadId, TimelineDirection.newer);

  /// 打开会话后的首窗。等价于旧控制器的 latest/reset，不把页当成目录事实。
  Future<void> loadLatestHistory(String threadId) =>
      _loadHistory(threadId, TimelineDirection.newer, replaceWindow: true);

  /// 运行中窗口追新：由权威 ChatView 窗口扩展并交回快照。
  ///
  /// 追新是向旧扩充操作：加载/失败/完成状态一律落在 older 边，与
  /// timeline 上边缘的重试指示对齐（旧控制器 `_loadChatWindow` 同语义）。
  Future<void> extendLatestHistory(String threadId) async {
    final store = ref.read(threadSessionStoreProvider(threadId).notifier);
    final window = await store.chatView();
    if (window == null || !ref.mounted) return;
    final epoch = ref.read(threadSessionStoreProvider(threadId)).streamEpoch;
    store.setHistoryLoading(TimelineDirection.older);
    try {
      final snapshot = await window.extendLatest();
      if (!ref.mounted ||
          ref.read(threadSessionStoreProvider(threadId)).streamEpoch != epoch) {
        if (ref.mounted) store.finishHistoryLoad();
        return;
      }
      store.applyChatSnapshot(
        snapshot,
        historyCompletion: ChatHistoryCompletion.older,
      );
      // 快照因低 version 被 merge path 早退时 loading 可能残留，防御性收尾。
      if (ref.read(threadSessionStoreProvider(threadId)).history.isLoading) {
        store.finishHistoryLoad();
      }
    } catch (error) {
      if (ref.mounted) {
        store.setHistoryError(TimelineDirection.older, error.toString());
      }
    }
  }

  /// 跳回实时底部：清锚点后聚焦权威窗口的 Latest。
  Future<void> jumpToLatest(String threadId) async {
    final store = ref.read(threadSessionStoreProvider(threadId).notifier);
    store.jumpToLatest();
    final window = await store.chatView();
    if (window == null || !ref.mounted) return;
    final epoch = ref.read(threadSessionStoreProvider(threadId)).streamEpoch;
    try {
      final snapshot = await window.focus(null);
      if (!ref.mounted ||
          ref.read(threadSessionStoreProvider(threadId)).streamEpoch != epoch) {
        return;
      }
      store.applyChatSnapshot(
        snapshot,
        historyCompletion: ChatHistoryCompletion.focus,
      );
    } catch (error) {
      if (ref.mounted) {
        store.setHistoryError(TimelineDirection.newer, error.toString());
      }
    }
  }

  /// 写入阅读锚点；浏览历史意图时同步聚焦权威窗口的历史条目。
  Future<void> updateTimelineAnchor(
    String threadId,
    TimelineAnchor anchor,
  ) async {
    final store = ref.read(threadSessionStoreProvider(threadId).notifier);
    store.setTimelineAnchor(anchor);
    if (anchor.readingIntent != TimelineReadingIntent.browseHistory) return;
    final window = await store.chatView();
    if (window == null || !ref.mounted) return;
    final epoch = ref.read(threadSessionStoreProvider(threadId)).streamEpoch;
    try {
      final snapshot = await window.focus(anchor.itemId);
      if (!ref.mounted ||
          ref.read(threadSessionStoreProvider(threadId)).streamEpoch != epoch) {
        return;
      }
      store.applyChatSnapshot(snapshot);
    } catch (_) {
      // 聚焦失败保留当前窗口与锚点；下一次滚动或翻页会重试。
    }
  }

  /// 可见条目正文补齐：对窗口内仍是预览的身份按 identity 展开。
  Future<void> ensureItemBodies(
    String threadId,
    Iterable<String> itemIds,
  ) async {
    for (final itemId in itemIds) {
      await _completeItemBody(threadId, itemId);
    }
  }

  /// 显式重试一次按身份的正文补齐（只对窗口内仍是预览的身份生效）。
  Future<void> loadItemBody(String threadId, String itemId) =>
      _completeItemBody(threadId, itemId, retry: true);

  Future<void> _completeItemBody(
    String threadId,
    String itemId, {
    bool retry = false,
  }) async {
    final session = ref.read(threadSessionStoreProvider(threadId));
    final history = session.history;
    if (!history.previewedItemIds.contains(itemId) ||
        history.loadingItemIds.contains(itemId)) {
      return;
    }
    if (!retry && history.itemBodyErrors.containsKey(itemId)) return;
    final store = ref.read(threadSessionStoreProvider(threadId).notifier);
    final window = await store.chatView();
    if (window == null || !ref.mounted) return;
    final latest = ref.read(threadSessionStoreProvider(threadId));
    if (!latest.history.previewedItemIds.contains(itemId) ||
        latest.history.loadingItemIds.contains(itemId)) {
      return;
    }
    final epoch = latest.streamEpoch;
    store.beginItemBodyLoad(itemId);
    try {
      final snapshot = await window.expandItem(itemId);
      if (!ref.mounted ||
          ref.read(threadSessionStoreProvider(threadId)).streamEpoch != epoch) {
        return;
      }
      if (snapshot == null) {
        // 身份仍在窗口、正文此刻取不到：保留预览与重试入口，不编造正文。
        store.markItemBodyPending(itemId);
        return;
      }
      store.applyChatSnapshot(snapshot);
    } catch (error) {
      if (ref.mounted &&
          ref.read(threadSessionStoreProvider(threadId)).streamEpoch == epoch) {
        store.failItemBodyLoad(itemId, error.toString());
      }
    }
  }

  Future<void> _applyThreadModelRoute({
    required String threadId,
    required String providerId,
    required String model,
    String? effort,
  }) async {
    final key = 'thread-route:$threadId';
    final target = CommandTarget(
      providerId: providerId,
      model: model,
      effort: effort,
    );
    final settings = ref.read(settingsStoreProvider.notifier);
    settings.beginCommand(key, target);
    try {
      if (!ref.read(settingsStoreProvider).configLoaded) {
        final refreshed = await ref
            .read(settingsCommandsProvider.notifier)
            .refreshCanonical();
        if (refreshed == null ||
            !ref.read(settingsStoreProvider).configLoaded) {
          throw StateError('Settings are not available yet.');
        }
      }
      final response = await retryRevisionConflict(
        () => _requestThreadModelRoute(
          threadId: threadId,
          providerId: providerId,
          model: model,
          effort: effort,
        ),
        refresh: () => _refreshRouteOwners(threadId),
      );
      if (!ref.mounted) return;
      settings.merge(response.settings);
      settings.clearCommand(key);
      _rememberWarning(threadId, response.warning);
    } catch (error) {
      if (ref.mounted) {
        settings.failCommand(
          key,
          typedCommandFailure(error, correlationId: 'client-thread-route'),
          target: target,
        );
      }
      rethrow;
    }
  }

  /// 两次 revision 都在尝试前从各自 owner 读取。响应 runtime 不进入 store。
  Future<ThreadModelRouteUpdateResult> _requestThreadModelRoute({
    required String threadId,
    required String providerId,
    required String model,
    String? effort,
  }) async {
    final session = ref.read(threadSessionStoreProvider(threadId));
    final route = session.runtime?.modelRoute;
    final target = _findModel(providerId, model);
    if (!session.hasSnapshot || route == null || target == null) {
      throw StateError('Selected thread model route is unavailable.');
    }
    return _api.setThreadModelRoute(
      threadId: threadId,
      expectedModelRouteRevision: route.revision,
      expectedSettingsRevision: ref
          .read(settingsStoreProvider)
          .settingsRevision,
      providerId: providerId,
      model: model,
      effort: effort ?? target.reasoningEfforts.firstOrNull,
    );
  }

  Future<bool> _refreshRouteOwners(String threadId) async {
    final settings = await ref
        .read(settingsCommandsProvider.notifier)
        .refreshCanonical();
    if (settings == null || !ref.mounted) return false;
    try {
      await _refreshSession(threadId);
    } catch (_) {
      // 下一轮使用最后一次观察到的 route。刷新失败不覆盖原冲突。
    }
    return true;
  }

  Future<void> _loadHistory(
    String threadId,
    TimelineDirection direction, {
    bool replaceWindow = false,
  }) async {
    if (!_historyInFlight.add(threadId)) return;
    final session = ref.read(threadSessionStoreProvider(threadId).notifier);
    final before = ref.read(threadSessionStoreProvider(threadId));
    final older = direction == TimelineDirection.older;
    final anchor = older
        ? before.history.olderCursor ?? before.items.firstOrNull?.id
        : before.history.newerCursor ?? before.items.lastOrNull?.id;
    final canPage =
        replaceWindow ||
        (anchor != null &&
            (older ? before.history.hasOlder : before.history.hasNewer));
    if (!before.hasSnapshot || before.history.isLoading || !canPage) {
      _historyInFlight.remove(threadId);
      return;
    }
    final epoch = before.history.epoch;
    session.setHistoryLoading(direction);
    try {
      final page = await _api.listTimelineItems(
        threadId,
        kind: replaceWindow
            ? TimelineQueryKind.latest
            : older
            ? TimelineQueryKind.before
            : TimelineQueryKind.after,
        itemId: replaceWindow ? null : anchor,
      );
      if (!ref.mounted) return;
      final latest = ref.read(threadSessionStoreProvider(threadId));
      if (latest.history.epoch != epoch) {
        session.finishHistoryLoad();
        return;
      }
      session.applyTimelinePage(
        page,
        direction,
        replaceWindow: replaceWindow,
        followBottom: replaceWindow,
      );
      if (ref.read(threadSessionStoreProvider(threadId)).history.isLoading) {
        session.finishHistoryLoad();
      }
    } catch (error) {
      if (ref.mounted &&
          ref.read(threadSessionStoreProvider(threadId)).history.epoch ==
              epoch) {
        session.setHistoryError(direction, error.toString());
      }
    } finally {
      _historyInFlight.remove(threadId);
    }
  }

  Future<void> _refreshSession(String threadId) async {
    final snapshot = await _api.readThreadSnapshot(threadId);
    if (!ref.mounted) return;
    ref
        .read(threadSessionStoreProvider(threadId).notifier)
        .applySnapshot(snapshot);
  }

  Future<void> _reloadProduct() async {
    final snapshot = await _api.readStudioState();
    if (!ref.mounted) return;
    applyProductSnapshot(ref, snapshot);
  }

  ProviderModelView? _findModel(String providerId, String model) {
    final providers =
        ref.read(settingsStoreProvider).canonical?.providers ?? const [];
    for (final provider in providers) {
      if (provider.id != providerId) continue;
      for (final candidate in provider.allModels) {
        if (candidate.slug == model) return candidate;
      }
    }
    return null;
  }

  StudioThread? _directoryThread(String threadId) {
    final directory = ref.read(threadDirectoryStoreProvider);
    for (final thread in directory.window.threads) {
      if (thread.id == threadId) return thread;
    }
    for (final thread in directory.overlayThreads) {
      if (thread.id == threadId) return thread;
    }
    return null;
  }

  bool _blocksThread(String threadId) =>
      _blocks(scope: RecoveryIssueScope.thread, threadId: threadId);

  bool _blocksProject(String projectId) =>
      _blocks(scope: RecoveryIssueScope.project, projectId: projectId);

  bool _blocks({
    required RecoveryIssueScope scope,
    String? projectId,
    String? threadId,
  }) {
    final issues = ref.read(recoveryStoreProvider).value?.values ?? const [];
    return issues.any(
      (issue) =>
          issue.blocksAccess &&
          issue.scope == scope &&
          (projectId == null || issue.projectId == projectId) &&
          (threadId == null || issue.threadId == threadId),
    );
  }

  void _rememberWarning(String threadId, String? warning) {
    final warnings = {...state.warnings};
    if (warning == null) {
      warnings.remove(threadId);
    } else {
      warnings[threadId] = warning;
    }
    if (_stringMapsEqual(warnings, state.warnings)) return;
    state = state.copyWith(warnings: warnings);
  }

  void _begin(String key, {required String label}) {
    _put(
      CommandStatus(
        key: key,
        phase: CommandPhase.pending,
        target: CommandTarget(label: label),
      ),
    );
  }

  void _clear(String key) {
    if (!state.commands.containsKey(key)) return;
    state = state.copyWith(commands: {...state.commands}..remove(key));
  }

  void _fail(String key, String id, Object error) {
    final existing = state.commands[key];
    _put(
      CommandStatus(
        key: key,
        phase: CommandPhase.failed,
        target: existing?.target ?? CommandTarget(label: id),
        error: typedCommandFailure(error, correlationId: 'client-thread'),
      ),
    );
  }

  void _put(CommandStatus status) {
    final commands = {...state.commands, status.key: status};
    if (commandMapsEqual(commands, state.commands)) return;
    state = state.copyWith(commands: commands);
  }

  StudioBridgeDataSource get _api => ref.read(studioBridgeDataSourceProvider);
}

class ThreadCommandBoard {
  const ThreadCommandBoard({
    this.commands = const {},
    this.warnings = const {},
  });

  final Map<String, CommandStatus> commands;
  final Map<String, String> warnings;

  ThreadCommandBoard copyWith({
    Map<String, CommandStatus>? commands,
    Map<String, String>? warnings,
  }) {
    return ThreadCommandBoard(
      commands: commands ?? this.commands,
      warnings: warnings ?? this.warnings,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ThreadCommandBoard &&
          commandMapsEqual(commands, other.commands) &&
          _stringMapsEqual(warnings, other.warnings);

  @override
  int get hashCode =>
      Object.hash(commandMapHash(commands), _stringMapHash(warnings));
}

bool _stringMapsEqual(Map<String, String> left, Map<String, String> right) {
  if (identical(left, right)) return true;
  if (left.length != right.length) return false;
  for (final entry in left.entries) {
    if (right[entry.key] != entry.value) return false;
  }
  return true;
}

int _stringMapHash(Map<String, String> values) => Object.hashAll(
  values.entries.map((entry) => Object.hash(entry.key, entry.value)),
);
