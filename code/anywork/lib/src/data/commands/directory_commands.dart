import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../domain/models/studio_models.dart';
import '../frb/studio_api.dart';
import '../repositories/studio_api_provider.dart';
import '../stores/lsp_store.dart';
import '../stores/mcp_store.dart';
import '../stores/persistence_store.dart';
import '../stores/provider_usage_store.dart';
import '../stores/recovery_store.dart';
import '../stores/selection_store.dart';
import '../stores/settings_store.dart';
import '../stores/skills_store.dart';
import '../stores/snapshot_fanout.dart';
import '../stores/thread_directory_store.dart';
import '../stores/thread_session_store.dart';
import 'command_lane.dart';

part 'directory_commands.g.dart';

/// 目录、选择与领域刷新命令。
///
/// 打开/归档等没有目录 revision 的响应不直接拼进目录，而是读取产品快照后走
/// [applyProductSnapshot]。模型目录刷新按 provider 去重。选择是本地事实，
/// 成功后才写入，不乐观改 canonical。
@Riverpod(keepAlive: true)
class DirectoryCommands extends _$DirectoryCommands {
  final CommandLane _lane = CommandLane();
  final Map<String, Future<void>> _catalogRefreshes = {};

  @override
  DirectoryCommandState build() => const DirectoryCommandState();

  Future<void> openProject(String path) {
    return _lane.enqueue(() async {
      final project = await _api.openProject(path);
      await _api.activateProject(project.id);
      if (!ref.mounted) return;
      final snapshot = await _reloadProduct();
      _selectProjectDefault(snapshot, project.id);
    });
  }

  /// 返回 true 仅当打开、激活并采用快照后，选中项目与请求身份一致。
  Future<bool> openRemoteProject(String alias, String path, {String? name}) {
    return _lane.enqueue(() async {
      try {
        var project = await _api.openRemoteProject(alias, path);
        if (name != null && name != project.name) {
          project = await _api.renameProject(project.id, name);
        }
        await _api.activateProject(project.id);
        if (!ref.mounted) return false;
        final snapshot = await _reloadProduct();
        _selectProjectDefault(snapshot, project.id);
        final selected = _selectedProject(snapshot);
        return selected != null &&
            selected.id == project.id &&
            selected.sshAlias == alias &&
            selected.path == project.path;
      } on Object {
        return false;
      }
    });
  }

  Future<void> selectProject(String projectId) {
    return _lane.enqueue(() async {
      if (ref.read(selectionStoreProvider).selectedProjectId == projectId) {
        return;
      }
      if (_blocksProject(projectId)) return;
      await _api.activateProject(projectId);
      if (!ref.mounted) return;
      final snapshot = await _reloadProduct();
      _selectProjectDefault(snapshot, projectId);
    });
  }

  Future<void> selectThread(String threadId) {
    return _lane.enqueue(() async {
      final thread = _directoryThread(threadId);
      if (thread == null || _blocksThread(threadId)) return;
      final selection = ref.read(selectionStoreProvider);
      if (selection.selectedThreadId == threadId) {
        ref.read(selectionStoreProvider.notifier).markOpened();
        return;
      }
      ref
          .read(selectionStoreProvider.notifier)
          .selectThread(projectId: thread.projectId, threadId: threadId);
    });
  }

  Future<void> selectAgentThread(String threadId) {
    return _lane.enqueue(() async {
      if (ref.read(selectionStoreProvider).selectedThreadId == threadId) {
        return;
      }
      final target = _directoryThread(threadId);
      if (target == null || _blocksThread(threadId)) return;
      final root = _selectedRoot();
      if (root != null && target.effectiveRootThreadId != root.id) return;
      ref
          .read(selectionStoreProvider.notifier)
          .selectThread(projectId: target.projectId, threadId: threadId);
    });
  }

  /// 启动恢复的待打开会话：清除 [SelectionStoreState.needsOpen]，让
  /// timeline/会话订阅按当前选择建流并请求首个历史窗口。
  ///
  /// recovery 阻塞访问时保持待打开状态，由用户解除阻塞后再次触发。
  Future<void> openSelectedThread() {
    return _lane.enqueue(() async {
      final selection = ref.read(selectionStoreProvider);
      final threadId = selection.selectedThreadId;
      if (threadId == null || !selection.needsOpen) return;
      if (_blocksThread(threadId)) return;
      ref.read(selectionStoreProvider.notifier).markOpened();
    });
  }

  Future<void> beginNewThread() {
    return _lane.enqueue(() async {
      final projectId = ref.read(selectionStoreProvider).selectedProjectId;
      if (projectId == null || _blocksProject(projectId)) return;
      ref.read(selectionStoreProvider.notifier).beginNewThread();
    });
  }

  Future<void> restoreThread(String threadId) {
    return _lane.enqueue(() async {
      final thread = await _api.restoreThread(threadId);
      if (!ref.mounted) return;
      await _reloadProduct();
      ref
          .read(selectionStoreProvider.notifier)
          .selectThread(projectId: thread.projectId, threadId: thread.id);
    });
  }

  Future<void> archiveProject(String projectId) {
    return _lane.enqueue(() async {
      if (_selectedProjectBusy(projectId)) return;
      // 只记录当前已加载窗口中的该项目会话。分页窗口之外的 id 不能当成已删除。
      final loadedIds = ref
          .read(threadDirectoryStoreProvider)
          .window
          .threads
          .where((thread) => thread.projectId == projectId)
          .map((thread) => thread.id)
          .toSet();
      await _api.archiveProject(projectId);
      if (!ref.mounted) return;
      await _reloadProduct();
      if (!ref.mounted) return;
      final remaining = ref
          .read(threadDirectoryStoreProvider)
          .window
          .threads
          .map((thread) => thread.id)
          .toSet();
      for (final id in loadedIds) {
        if (!remaining.contains(id)) releaseThreadSession(ref, id);
      }
    });
  }

  Future<ThreadDirectoryPage> queryThreads(
    DirectoryQuery query, {
    String? cursor,
    int limit = 50,
  }) async {
    final page = await _api.queryThreads(query, cursor: cursor, limit: limit);
    if (ref.mounted) {
      // 搜索命中但不在当前窗口的线程并入 overlay，保证 selectThread 可定位。
      ref
          .read(threadDirectoryStoreProvider.notifier)
          .mergeOverlayThreads(page.threads);
    }
    return page;
  }

  Future<void> loadMoreThreads() {
    return _lane.enqueue(() async {
      final directory = ref.read(threadDirectoryStoreProvider);
      if (!directory.loaded ||
          directory.window.isLoading ||
          !directory.hasMore) {
        return;
      }
      final store = ref.read(threadDirectoryStoreProvider.notifier);
      store.setLoading(true);
      _setLoadMoreError(null);
      try {
        final page = await _api.listThreadsPage(cursor: directory.nextCursor);
        if (!ref.mounted) return;
        store.appendPage(page);
      } catch (error) {
        if (!ref.mounted) return;
        ref.read(threadDirectoryStoreProvider.notifier).setLoading(false);
        _setLoadMoreError(error.toString());
        rethrow;
      }
    });
  }

  Future<void> refreshModelCatalog(String providerId) {
    final existing = _catalogRefreshes[providerId];
    if (existing != null) return existing;
    final operation = _refreshModelCatalog(providerId);
    _catalogRefreshes[providerId] = operation;
    return operation.whenComplete(() {
      if (identical(_catalogRefreshes[providerId], operation)) {
        _catalogRefreshes.remove(providerId);
      }
    });
  }

  Future<void> refreshProviderUsages() async {
    final snapshot = await _api.checkProviderUsage();
    if (!ref.mounted) return;
    ref.read(providerUsageStoreProvider.notifier).apply(snapshot);
  }

  Future<void> refreshSkillsState() async {
    final projectId = ref.read(selectionStoreProvider).selectedProjectId;
    if (projectId == null) return;
    final snapshot = await _api.readSkillsState(projectId);
    if (!ref.mounted) return;
    ref.read(skillsStoreProvider(projectId).notifier).apply(snapshot);
  }

  Future<List<String>> discoverSkills() async {
    final projectId = ref.read(selectionStoreProvider).selectedProjectId;
    if (projectId == null) return const [];
    final snapshot = await _api.discoverSkills(projectId);
    if (ref.mounted) {
      ref.read(skillsStoreProvider(projectId).notifier).apply(snapshot);
    }
    return snapshot.skills;
  }

  Future<SkillSearchResultView?> searchSkills(
    String query, {
    int limit = 50,
  }) async {
    final projectId = ref.read(selectionStoreProvider).selectedProjectId;
    if (projectId == null) return null;
    return _api.searchSkills(projectId, query, limit: limit);
  }

  Future<void> refreshMcpState() => _applyMcp(_api.readMcpState);

  Future<void> resetMcpServer(String serverId) =>
      _applyMcp(() => _api.resetMcpServer(serverId));

  Future<void> resetAllMcp() => _applyMcp(_api.resetAllMcp);

  Future<void> refreshLspState() => _applyLsp(_api.readLspState);

  Future<void> probeLspServer() async {
    final projectId = ref.read(selectionStoreProvider).selectedProjectId;
    if (projectId == null) return;
    await _applyLsp(() => _api.probeLspServer(projectId));
  }

  Future<void> repairLspServer(String serverId) async {
    final projectId = ref.read(selectionStoreProvider).selectedProjectId;
    if (projectId == null) return;
    await _applyLsp(() => _api.repairLspServer(projectId, serverId));
  }

  Future<void> resetLspServer(String serverId) async {
    final projectId = ref.read(selectionStoreProvider).selectedProjectId;
    if (projectId == null) return;
    await _applyLsp(() => _api.resetLspServer(projectId, serverId));
  }

  Future<void> resetLspWorkspace() async {
    final projectId = ref.read(selectionStoreProvider).selectedProjectId;
    if (projectId == null) return;
    await _applyLsp(() => _api.resetLspWorkspace(projectId));
  }

  Future<void> retryRecovery() async {
    final snapshot = await _api.retryRecovery();
    if (!ref.mounted) return;
    ref.read(recoveryStoreProvider.notifier).apply(snapshot);
  }

  Future<void> cleanupPreservedWorktree(WorktreeRecoveryPreview worktree) {
    return _api.cleanupPreservedWorktree(
      ownerKind: worktree.ownerKind.id,
      ownerThreadId: worktree.ownerThreadId,
      expectedLeaseRevision: worktree.leaseRevision,
    );
  }

  Future<void> retryPersistence() async {
    final snapshot = await _api.retryPersistence();
    if (!ref.mounted) return;
    ref.read(persistenceStoreProvider.notifier).applyState(snapshot);
  }

  /// raw 队列观测没有发布 revision，不写入 persistence store。
  Future<PersistenceQueueSnapshot> retryThreadHistory(
    String threadId,
    int faultGeneration,
  ) {
    return _api.retryThreadHistory(threadId, faultGeneration);
  }

  Future<PersistenceQueueSnapshot> resumeThreadHistory(
    String threadId,
    int faultGeneration,
  ) {
    return _api.resumeThreadHistory(threadId, faultGeneration);
  }

  Future<void> _refreshModelCatalog(String providerId) async {
    final snapshot = await _api.refreshModelCatalog(providerId);
    if (!ref.mounted) return;
    ref.read(settingsStoreProvider.notifier).merge(snapshot);
  }

  Future<void> _applyMcp(Future<McpStateSnapshot> Function() command) async {
    final snapshot = await command();
    if (!ref.mounted) return;
    ref.read(mcpStoreProvider.notifier).apply(snapshot);
  }

  Future<void> _applyLsp(Future<LspStateSnapshot> Function() command) async {
    final snapshot = await command();
    if (!ref.mounted) return;
    ref.read(lspStoreProvider.notifier).apply(snapshot);
  }

  Future<StudioState> _reloadProduct() async {
    final snapshot = await _api.readStudioState();
    if (ref.mounted) applyProductSnapshot(ref, snapshot);
    return snapshot;
  }

  void _selectProjectDefault(StudioState snapshot, String projectId) {
    if (!snapshot.projects.any((project) => project.id == projectId)) return;
    final threadId = snapshot.threads
        .where((thread) => thread.isRoot && thread.projectId == projectId)
        .firstOrNull
        ?.id;
    final selection = ref.read(selectionStoreProvider.notifier);
    if (threadId == null) {
      selection.selectProject(projectId);
      return;
    }
    selection.selectThread(projectId: projectId, threadId: threadId);
  }

  StudioProject? _selectedProject(StudioState snapshot) {
    final selectedId = ref.read(selectionStoreProvider).selectedProjectId;
    return snapshot.projects
        .where((project) => project.id == selectedId)
        .firstOrNull;
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

  StudioThread? _selectedRoot() {
    final selectedId = ref.read(selectionStoreProvider).selectedThreadId;
    if (selectedId == null) return null;
    final selected = _directoryThread(selectedId);
    if (selected == null) return null;
    final rootId = selected.effectiveRootThreadId;
    final root = _directoryThread(rootId);
    return root != null && root.isRoot ? root : null;
  }

  bool _selectedProjectBusy(String projectId) {
    final selection = ref.read(selectionStoreProvider);
    if (selection.selectedProjectId != projectId) return false;
    final threadId = selection.selectedThreadId;
    if (threadId == null) return false;
    return ref
            .read(threadSessionStoreProvider(threadId))
            .activeTurn
            ?.state
            .isBusy ??
        false;
  }

  bool _blocksProject(String projectId) =>
      _blocks(scope: RecoveryIssueScope.project, projectId: projectId);

  bool _blocksThread(String threadId) =>
      _blocks(scope: RecoveryIssueScope.thread, threadId: threadId);

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

  void _setLoadMoreError(String? message) {
    if (state.loadMoreError == message) return;
    state = DirectoryCommandState(loadMoreError: message);
  }

  StudioBridgeDataSource get _api => ref.read(studioBridgeDataSourceProvider);
}

class DirectoryCommandState {
  const DirectoryCommandState({this.loadMoreError});

  final String? loadMoreError;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DirectoryCommandState && loadMoreError == other.loadMoreError;

  @override
  int get hashCode => loadMoreError.hashCode;
}
