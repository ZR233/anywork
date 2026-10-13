import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../domain/models/studio_models.dart';
import '../../domain/models/timeline_commands.dart';
import '../frb/studio_api.dart';
import '../repositories/studio_api_provider.dart';
import '../stores/chat_view_metrics.dart';
import '../stores/domain_sync.dart';
import '../stores/recovery_store.dart';
import '../stores/selection_store.dart';
import '../stores/settings_store.dart';
import '../stores/snapshot_fanout.dart';
import '../stores/thread_directory_store.dart';
import '../stores/thread_session_store.dart';
import 'command_lane.dart';
import 'settings_commands.dart';

part 'thread_commands.g.dart';

/// 会话命令 lane。
///
/// 命令在提交时**冻结资源身份**（threadId/projectId/turnId）：排队期间切换会话不会改变命令
/// 目标；执行时只重新读取该资源自身的版本与合法性（design/25 §25.7）。
///
/// route 更新与设置写入共用 settings lane，并按双 revision rebase。响应里的
/// runtime 不是第二事实源：只合并 settings，route 本身等 Thread 有序流。
/// 其他命令直通数据源；命令成功后不重读聚合状态——目录增量、Thread 快照与聊天内容由
/// 各自 owner 的流交付（design/25 §25.5）。
@Riverpod(keepAlive: true)
class ThreadCommands extends _$ThreadCommands {
  final CommandLane _lane = CommandLane();
  final CommandLane _stopLane = CommandLane();

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
    // 点击时冻结目标：排队期间切换会话不改变命令目标。
    final threadId = ref.read(selectionStoreProvider).selectedThreadId;
    if (threadId == null) return Future<void>.value();
    return _lane.enqueue(() async {
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
      // 命令后不显式重读：mode 由目录增量交付、mode 默认 route 由 Thread 有序流
      // 交付（design/25 §25.5）。补偿式重读会让同一事实多出第二条合并路径，并让
      // 「帧没到」这种缺陷在验收里不可见。
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
      final interactions = ref
          .read(threadSessionStoreProvider(threadId))
          .interactions;
      final active = [...interactions]
        ..sort(
          (left, right) =>
              interactionPriority(left.kind)
                  .compareTo(interactionPriority(right.kind)),
        );
      if (active.firstOrNull?.id != interactionId) {
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
        if (ref.mounted) {
          // 目录条目由 owner 的目录增量交付（commit_directory 已在命令内发布）；
          // 命令成功后不重读聚合状态（design/25 §25.5）。
          ref
              .read(selectionStoreProvider.notifier)
              .selectThread(projectId: projectId, threadId: result.thread.id);
        }
        _clear(key);
        return result;
      } catch (error) {
        _fail(key, projectId, error);
        rethrow;
      }
    });
  }

  /// 停止是独立的可取消控制入口：不排在归档/创建/长查询后面，也不按「当前是否选中」
  /// 过滤目标——调用时冻结的 threadId + turnId 就是命令目标。
  Future<void> stop(String threadId) {
    final turn = ref.read(threadSessionStoreProvider(threadId)).activeTurn;
    if (turn == null || !turn.state.isBusy) return Future<void>.value();
    final turnId = turn.turnId;
    return _stopLane.enqueue(() async {
      final latest = ref.read(threadSessionStoreProvider(threadId)).activeTurn;
      if (latest == null || latest.turnId != turnId || !latest.state.isBusy) {
        return;
      }
      final key = 'stop:$threadId';
      _begin(key, label: threadId);
      try {
        await _api.interruptTurn(threadId, turnId);
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
        // 目录增量已在命令内发布（commit_directory），不重读聚合状态。
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
        if (ref.mounted) {
          for (final id in result.removedThreadIds) {
            releaseThreadSession(ref, id);
          }
          final selected = ref.read(selectionStoreProvider).selectedThreadId;
          if (selected != null && result.removedThreadIds.contains(selected)) {
            ref
                .read(selectionStoreProvider.notifier)
                .replaceRemovedThread(result.nextRoot?.id);
          }
        }
        _clear(key);
      } catch (error) {
        _fail(key, threadId, error);
        rethrow;
      }
    });
  }

  Future<void> loadOlderHistory(String threadId) =>
      _loadWindow(threadId, TimelineDirection.older);

  Future<void> loadNewerHistory(String threadId) =>
      _loadWindow(threadId, TimelineDirection.newer);

  /// 打开会话后的首窗：确保权威内容绑定已建立，首帧 Reset 由内容泵交付。
  Future<void> loadLatestHistory(String threadId) async {
    await ref.read(threadSessionStoreProvider(threadId).notifier).chatView();
  }

  /// 运行中窗口追新：向旧扩充操作；loading 落在 older 边，与 timeline 上边缘的重试指示对齐。
  Future<void> extendLatestHistory(String threadId) async {
    final session = ref.read(threadSessionStoreProvider(threadId));
    if (!session.history.canExtendLatest || session.history.isLoading) return;
    ChatViewMetrics.extendLatestCalls += 1;
    final store = ref.read(threadSessionStoreProvider(threadId).notifier);
    final token = store.beginHistoryOp(TimelineDirection.older);
    if (token == null) return;
    try {
      final window = await store.chatView();
      if (window == null || !ref.mounted) {
        store.failHistoryOp(token, 'Chat window is unavailable');
        return;
      }
      final latest = ref.read(threadSessionStoreProvider(threadId));
      if (!latest.history.canExtendLatest) {
        store.observeHistoryOp(
          token,
          StudioChatReceipt(
            operationId: token,
            version: latest.chatVersion ?? 0,
            retained: true,
          ),
        );
        return;
      }
      final receipt = await window.extendLatest();
      if (ref.mounted) store.observeHistoryOp(token, receipt);
    } catch (error) {
      if (ref.mounted) store.failHistoryOp(token, error.toString());
    }
  }

  /// 跳回实时底部：清锚点后聚焦权威窗口的 Latest；Reset 仍由内容泵交付。
  Future<void> jumpToLatest(String threadId) async {
    final store = ref.read(threadSessionStoreProvider(threadId).notifier);
    store.jumpToLatest();
    final window = await store.chatView();
    if (window == null || !ref.mounted) return;
    try {
      await window.focus(null);
      store.settleViewFocus(null, succeeded: true);
    } catch (error) {
      store.settleViewFocus(null, succeeded: false);
      if (ref.mounted) {
        store.setHistoryError(TimelineDirection.newer, error.toString());
      }
    }
  }

  /// 写入阅读锚点；只有带定位动作的锚点才允许改变后端窗口焦点。
  ///
  /// 普通窗口内滚动只更新锚点：后端焦点不变，窗口也不移动。此前用「上一次锚点」去重，
  /// 于是每换一个顶行都会 focus 一次，而后端 focus 变化会让内容流发 Reset——滚动被放大成
  /// 整窗重载。去重因此只依据已确认焦点与同一目标的在途请求；失败后同一目标仍可重试。
  Future<void> updateTimelineAnchor(
    String threadId,
    TimelineAnchor anchor, {
    TimelineViewAction? viewAction,
  }) async {
    final store = ref.read(threadSessionStoreProvider(threadId).notifier);
    store.setTimelineAnchor(anchor);
    if (viewAction == null ||
        anchor.readingIntent != TimelineReadingIntent.browseHistory) {
      return;
    }
    // 已确认焦点就是同一个条目时，这一次定位动作不产生新的后端请求。
    if (!store.requestViewFocus(anchor.itemId)) {
      ChatViewMetrics.redundantFocusSkipped += 1;
      return;
    }
    final window = await store.chatView();
    if (window == null) {
      store.settleViewFocus(anchor.itemId, succeeded: false);
      return;
    }
    try {
      await window.focus(anchor.itemId);
      store.settleViewFocus(anchor.itemId, succeeded: true);
    } catch (_) {
      // 聚焦失败保留当前窗口与锚点；下一次同目标定位动作会重试。
      store.settleViewFocus(anchor.itemId, succeeded: false);
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
    store.beginItemBodyLoad(itemId);
    try {
      final receipt = await window.expandItem(itemId);
      if (!ref.mounted) return;
      if (!receipt.retained) {
        // 身份仍在窗口、正文此刻取不到：保留预览与重试入口，不编造正文。
        store.markItemBodyPending(itemId);
        return;
      }
      // 完整正文已保留进权威窗口：由内容泵的下一次交付写进镜像，帧到达时
      // 预览标记消失、`_syncItemBody` 自动清掉 loading，不在命令路径伪造正文。
    } catch (error) {
      if (ref.mounted) {
        store.failItemBodyLoad(itemId, error.toString());
      }
    }
  }

  /// 窗口内按方向翻一页：控制操作只取回执，窗口移动由内容泵以 Reset/Patch 交付。
  Future<void> _loadWindow(String threadId, TimelineDirection direction) async {
    final session = ref.read(threadSessionStoreProvider(threadId));
    final history = session.history;
    final older = direction == TimelineDirection.older;
    final canPage = older ? history.hasOlder : history.hasNewer;
    if (!session.hasSnapshot || history.isLoading || !canPage) return;
    if (older) {
      ChatViewMetrics.loadOlderCalls += 1;
    } else {
      ChatViewMetrics.loadNewerCalls += 1;
    }
    final store = ref.read(threadSessionStoreProvider(threadId).notifier);
    final token = store.beginHistoryOp(direction);
    if (token == null) return;
    try {
      final window = await store.chatView();
      if (window == null || !ref.mounted) {
        store.failHistoryOp(token, 'Chat window is unavailable');
        return;
      }
      final latest = ref.read(threadSessionStoreProvider(threadId)).history;
      final stillCanPage = older ? latest.hasOlder : latest.hasNewer;
      if (!stillCanPage) {
        store.observeHistoryOp(
          token,
          StudioChatReceipt(
            operationId: token,
            version:
                ref.read(threadSessionStoreProvider(threadId)).chatVersion ?? 0,
            retained: true,
          ),
        );
        return;
      }
      final receipt = await window.load(direction);
      if (ref.mounted) store.observeHistoryOp(token, receipt);
    } catch (error) {
      if (ref.mounted) store.failHistoryOp(token, error.toString());
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

  Future<void> _refreshSession(String threadId) async {
    final snapshot = await _api.readThreadSnapshot(threadId);
    if (!ref.mounted) return;
    ref
        .read(threadSessionStoreProvider(threadId).notifier)
        .applySnapshot(snapshot);
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
      identical(other, this) ||
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
