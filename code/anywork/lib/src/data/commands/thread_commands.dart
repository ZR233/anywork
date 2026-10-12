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
    for (final thread
        in ref.read(threadDirectoryStoreProvider).window.threads) {
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
