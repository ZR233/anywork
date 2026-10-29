import '../../../models.dart';
import '../../../studio_ports.dart';
import '../../../anywork_client.dart' show ReadModel;
import '../anywork_client.dart';
import '../agent_directory_queries.dart';
import 'command_lane.dart';

class DirectoryCommands extends ReadModel<DirectoryCommandState> {
  DirectoryCommands(this._client) : super(const DirectoryCommandState());
  final AnyworkClient _client;
  final CommandLane _lane = CommandLane();

  Future<void> close() {
    _lane.seal();
    return _lane.join();
  }

  Future<void> openProject(String path) {
    return _navigate((intent) async {
      _throwIfAccessBlocked(projectId: null);
      final project = await _api.openProject(path);
      if (!_ownsNavigation(intent)) return;
      _throwIfAccessBlocked(projectId: project.id);
      if (_shouldActivateProject(project.id)) {
        await _api.activateProject(project.id);
      }
      if (!_ownsNavigation(intent)) return;
      _selectProjectDefault(project.id);
    });
  }

  /// 返回 true 仅当打开、激活并采用快照后，选中项目与请求身份一致。
  Future<bool> openRemoteProject(String alias, String path, {String? name}) {
    final intent = _client.selection.beginNavigation();
    return _lane.enqueue(() async {
      if (!_ownsNavigation(intent)) return false;
      try {
        _throwIfAccessBlocked(projectId: null);
        var project = await _api.openRemoteProject(alias, path);
        if (!_ownsNavigation(intent)) return false;
        _throwIfAccessBlocked(projectId: project.id);
        if (name != null && name != project.name) {
          project = await _api.renameProject(project.id, name);
          if (!_ownsNavigation(intent)) return false;
        }
        if (_shouldActivateProject(project.id)) {
          await _api.activateProject(project.id);
        }
        if (!_ownsNavigation(intent)) return false;
        _selectProjectDefault(project.id);
        final selected = project;
        return selected.id == project.id &&
            selected.sshAlias == alias &&
            selected.path == project.path;
      } on StudioFailure {
        rethrow;
      } on Object {
        return false;
      }
    });
  }

  Future<void> selectProject(String projectId) {
    return _navigate((intent) async {
      _throwIfAccessBlocked(projectId: projectId);
      if (_client.selection.state.selectedProjectId == projectId) {
        return;
      }
      if (_shouldActivateProject(projectId)) {
        await _api.activateProject(projectId);
      }
      if (!_ownsNavigation(intent)) return;
      _selectProjectDefault(projectId);
    });
  }

  Future<void> selectThread(String threadId) {
    return _navigate((_) async {
      final thread = _directoryThread(threadId);
      if (thread == null) return;
      _throwIfAccessBlocked(projectId: thread.projectId, threadId: threadId);
      final selection = _client.selection.state;
      if (selection.selectedThreadId == threadId) {
        _client.selection.markOpened();
        return;
      }
      _client.selection.selectThread(
        projectId: thread.projectId,
        threadId: threadId,
      );
    });
  }

  Future<void> selectAgentThread(String threadId) {
    return _navigate((intent) => _selectAgentThread(threadId, intent));
  }

  Future<void> _selectAgentThread(String threadId, int intent) async {
    final selected = _client.selection.state;
    _throwIfAccessBlocked(
      projectId: selected.selectedProjectId,
      threadId: threadId,
    );
    final root = _selectedRootId();
    if (root == null ||
        !_rootMembers(root).any((agent) => agent.threadId == threadId))
      return;
    bool isCurrent() =>
        _ownsNavigation(intent) &&
        identical(_client.selection.state, selected) &&
        _selectedRootId() == root &&
        _rootMembers(root).any((agent) => agent.threadId == threadId);
    var target = _directoryThread(threadId);
    if (target == null) {
      try {
        target = await _api.readThread(threadId);
      } catch (_) {
        if (!isCurrent()) return;
        rethrow;
      }
      // A newer intent revokes publication immediately, even before its
      // command reaches the front of the serial lane. Still join this read.
      if (!_ownsNavigation(intent) ||
          !identical(_client.selection.state, selected)) {
        return;
      }
      _throwIfAccessBlocked(
        projectId: selected.selectedProjectId,
        threadId: threadId,
      );
      if (!isCurrent()) return;
      if (target.id != threadId ||
          target.effectiveRootThreadId != root ||
          target.projectId != selected.selectedProjectId) {
        throw const StudioFailure(
          code: StudioFailureCode.protocol,
          message: 'Selected agent metadata did not match its canonical root',
          retryable: false,
          correlationId: 'client-select-agent',
        );
      }
      _client.threadDirectory.mergeOverlayThreads([target]);
    }
    if (target.effectiveRootThreadId != root ||
        target.projectId != selected.selectedProjectId)
      return;
    _throwIfAccessBlocked(projectId: target.projectId, threadId: threadId);
    _client.selection.selectThread(
      projectId: target.projectId,
      threadId: threadId,
    );
  }

  /// 启动恢复的待打开会话：清除 [SelectionStoreState.needsOpen]，让
  /// timeline/会话订阅按当前选择建流并请求首个历史窗口。
  ///
  /// recovery 阻塞访问时保持待打开状态，由用户解除阻塞后再次触发。
  Future<void> openSelectedThread() {
    return _navigate((intent) async {
      final selection = _client.selection.state;
      final threadId = selection.selectedThreadId;
      if (threadId == null || !selection.needsOpen) return;
      _throwIfAccessBlocked(
        projectId: selection.selectedProjectId,
        threadId: threadId,
      );
      if (_directoryThread(threadId) == null) {
        await _selectAgentThread(threadId, intent);
        return;
      }
      _client.selection.markOpened();
    });
  }

  /// A project-scoped new-session action is one navigation intent. Do not
  /// compose selectProject().then(beginNewThread), which can revive old intent.
  Future<void> beginNewThread({String? projectId}) {
    return _navigate((intent) async {
      final target = projectId ?? _client.selection.state.selectedProjectId;
      if (target == null) return;
      _throwIfAccessBlocked(projectId: target);
      if (_client.selection.state.selectedProjectId != target) {
        if (_shouldActivateProject(target)) {
          await _api.activateProject(target);
          if (!_ownsNavigation(intent)) return;
        }
      }
      _client.selection.selectProject(target);
    });
  }

  Future<void> restoreThread(String threadId) {
    return _navigate((intent) async {
      _throwIfAccessBlocked(
        projectId: _projectIdForThread(threadId),
        threadId: threadId,
      );
      final thread = await _api.restoreThread(threadId);
      if (!_ownsNavigation(intent)) return;
      _throwIfAccessBlocked(projectId: thread.projectId, threadId: thread.id);
      _client.selection.selectThread(
        projectId: thread.projectId,
        threadId: thread.id,
      );
    });
  }

  Future<void> archiveProject(String projectId) {
    if (_client.selection.state.selectedProjectId == projectId) {
      _client.selection.beginNavigation();
    }
    return _lane.enqueue(() async {
      if (_selectedProjectBusy(projectId)) return;
      // 只记录当前已加载窗口中的该项目会话。分页窗口之外的 id 不能当成已删除。
      final loadedIds = _client.threadDirectory.state.window.threads
          .where((thread) => thread.projectId == projectId)
          .map((thread) => thread.id)
          .toSet();
      // Capture logical draft owners before directory removal can arrive.
      final draftOwners = _client.projectComposers(projectId);
      await _api.archiveProject(projectId);
      if (_client.isClosed) return;
      await _client.discardProjectDrafts(projectId, draftOwners);
      for (final id in loadedIds) {
        _client.releaseSession(id);
      }
    });
  }

  Future<ThreadDirectoryPage> queryThreads(
    DirectoryQuery query, {
    String? cursor,
    int limit = 50,
  }) => _lane.run(() async {
    final page = await _api.queryThreads(query, cursor: cursor, limit: limit);
    if (!_client.isClosed) {
      // 搜索命中但不在当前窗口的线程并入 overlay，保证 selectThread 可定位。
      _client.threadDirectory.mergeOverlayThreads(page.threads);
    }
    return page;
  });

  Future<void> loadMoreThreads() {
    return _lane.enqueue(() async {
      final directory = _client.threadDirectory.state;
      if (!directory.loaded ||
          directory.window.isLoading ||
          !directory.hasMore) {
        return;
      }
      final store = _client.threadDirectory;
      store.setLoading(true);
      _setLoadMoreError(null);
      try {
        final page = await _api.listThreadsPage(cursor: directory.nextCursor);
        if (_client.isClosed) return;
        store.appendPage(page);
      } catch (error) {
        if (_client.isClosed) return;
        _client.threadDirectory.setLoading(false);
        _setLoadMoreError(error.toString());
        rethrow;
      }
    });
  }

  Future<void> refreshSkillsState() => _lane.run(() async {
    final projectId = _client.selection.state.selectedProjectId;
    if (projectId == null) return;
    final snapshot = await _api.readSkillsState(projectId);
    if (_client.isClosed) return;
    _client.skills(projectId).apply(snapshot);
  });

  Future<List<String>> discoverSkills() => _lane.run(() async {
    final projectId = _client.selection.state.selectedProjectId;
    if (projectId == null) return const [];
    final snapshot = await _api.discoverSkills(projectId);
    if (!_client.isClosed) {
      _client.skills(projectId).apply(snapshot);
    }
    return snapshot.skills;
  });

  Future<SkillSearchResultView?> searchSkills(String query, {int limit = 50}) =>
      _lane.run(() async {
        final projectId = _client.selection.state.selectedProjectId;
        if (projectId == null) return null;
        return _api.searchSkills(projectId, query, limit: limit);
      });

  Future<void> refreshMcpState() => _applyMcp(_api.readMcpState);

  Future<void> resetMcpServer(String serverId) =>
      _applyMcp(() => _api.resetMcpServer(serverId));

  Future<void> resetAllMcp() => _applyMcp(_api.resetAllMcp);

  Future<void> refreshLspState() => _applyLsp(_api.readLspState);

  Future<void> probeLspServer() => _lane.run(() async {
    final projectId = _client.selection.state.selectedProjectId;
    if (projectId == null) return;
    await _applyLsp(() => _api.probeLspServer(projectId));
  });

  Future<void> repairLspServer(String serverId) => _lane.run(() async {
    final projectId = _client.selection.state.selectedProjectId;
    if (projectId == null) return;
    await _applyLsp(() => _api.repairLspServer(projectId, serverId));
  });

  Future<void> resetLspServer(String serverId) => _lane.run(() async {
    final projectId = _client.selection.state.selectedProjectId;
    if (projectId == null) return;
    await _applyLsp(() => _api.resetLspServer(projectId, serverId));
  });

  Future<void> resetLspWorkspace() => _lane.run(() async {
    final projectId = _client.selection.state.selectedProjectId;
    if (projectId == null) return;
    await _applyLsp(() => _api.resetLspWorkspace(projectId));
  });

  Future<void> retryRecovery() => _lane.run(() async {
    final snapshot = await _api.retryRecovery();
    if (_client.isClosed) return;
    _client.recovery.apply(snapshot);
  });

  Future<void> cleanupPreservedWorktree(WorktreeRecoveryPreview worktree) =>
      _lane.run(() async {
        return _api.cleanupPreservedWorktree(
          ownerKind: worktree.ownerKind.id,
          ownerThreadId: worktree.ownerThreadId,
          expectedLeaseRevision: worktree.leaseRevision,
        );
      });

  Future<void> retryPersistence() => _lane.run(() async {
    final snapshot = await _api.retryPersistence();
    if (_client.isClosed) return;
    _client.persistence.applyState(snapshot);
  });

  /// raw 队列观测没有发布 revision，不写入 persistence store。
  Future<PersistenceQueueSnapshot> retryThreadHistory(
    String threadId,
    int faultGeneration,
  ) => _lane.run(() async {
    return _api.retryThreadHistory(threadId, faultGeneration);
  });

  Future<PersistenceQueueSnapshot> resumeThreadHistory(
    String threadId,
    int faultGeneration,
  ) => _lane.run(() async {
    _throwIfExecutionBlocked(
      projectId: _projectIdForThread(threadId),
      threadId: threadId,
    );
    return _api.resumeThreadHistory(threadId, faultGeneration);
  });

  Future<void> _applyMcp(Future<McpStateSnapshot> Function() command) =>
      _lane.run(() async {
        final snapshot = await command();
        if (_client.isClosed) return;
        _client.mcp.apply(snapshot);
      });

  Future<void> _applyLsp(Future<LspStateSnapshot> Function() command) =>
      _lane.run(() async {
        final snapshot = await command();
        if (_client.isClosed) return;
        _client.lsp.apply(snapshot);
      });

  bool _ownsNavigation(int intent) =>
      !_client.isClosed && _client.selection.isCurrentNavigation(intent);

  Future<void> _navigate(Future<void> Function(int intent) action) {
    final intent = _client.selection.beginNavigation();
    return _lane.enqueue(() async {
      if (!_ownsNavigation(intent)) return;
      try {
        await action(intent);
      } catch (_) {
        // Current failures stay visible. A superseded read must not deliver a
        // stale error to the menu after a newer navigation has been accepted.
        if (_ownsNavigation(intent)) rethrow;
      }
    });
  }

  void _selectProjectDefault(String projectId) {
    final threadId = _client.threadDirectory.state.window.threads
        .where(
          (thread) =>
              thread.isRoot &&
              thread.projectId == projectId &&
              _accessBlocker(
                    projectId: thread.projectId,
                    threadId: thread.id,
                  ) ==
                  null,
        )
        .firstOrNull
        ?.id;
    if (threadId == null) {
      _client.selection.selectProject(projectId);
    } else {
      _client.selection.selectThread(projectId: projectId, threadId: threadId);
    }
  }

  StudioThread? _directoryThread(String threadId) {
    final directory = _client.threadDirectory.state;
    for (final thread in directory.window.threads) {
      if (thread.id == threadId) return thread;
    }
    for (final thread in directory.overlayThreads) {
      if (thread.id == threadId) return thread;
    }
    return null;
  }

  String? _selectedRootId() => AgentDirectoryQueries.rootThreadId(
    threadId: _client.selection.state.selectedThreadId,
    agents: _client.project.state.agents?.values ?? const [],
    threads: [
      ..._client.threadDirectory.state.window.threads,
      ..._client.threadDirectory.state.overlayThreads,
    ],
  );

  List<StudioAgentView> _rootMembers(String rootId) =>
      AgentDirectoryQueries.forRoot(
        rootThreadId: rootId,
        agents: _client.project.state.agents?.values ?? const [],
        threads: [
          ..._client.threadDirectory.state.window.threads,
          ..._client.threadDirectory.state.overlayThreads,
        ],
      );

  bool _selectedProjectBusy(String projectId) {
    final selection = _client.selection.state;
    if (selection.selectedProjectId != projectId) return false;
    final threadId = selection.selectedThreadId;
    if (threadId == null) return false;
    return _client.session(threadId).state.activeTurn?.state.isBusy ?? false;
  }

  StudioRecoveryIssue? _accessBlocker({
    required String? projectId,
    String? threadId,
  }) => recoveryIssueBlockingAccess(
    _client.recovery.state.value?.values ?? const [],
    projectId: projectId,
    threadId: threadId,
  );

  StudioRecoveryIssue? _executionBlocker({
    required String? projectId,
    String? threadId,
  }) => recoveryIssueBlockingExecution(
    _client.recovery.state.value?.values ?? const [],
    projectId: projectId,
    threadId: threadId,
  );

  void _throwIfAccessBlocked({required String? projectId, String? threadId}) {
    final issue = _accessBlocker(projectId: projectId, threadId: threadId);
    if (issue != null) throw issue.blockedFailure();
  }

  void _throwIfExecutionBlocked({
    required String? projectId,
    String? threadId,
  }) {
    final issue = _executionBlocker(projectId: projectId, threadId: threadId);
    if (issue != null) throw issue.blockedFailure();
  }

  String? _projectIdForThread(String threadId) {
    final directoryProjectId = _directoryThread(threadId)?.projectId;
    if (directoryProjectId != null) return directoryProjectId;
    final workspaceProjectId = _client
        .existingSession(threadId)
        ?.state
        .workspace
        ?.thread
        .projectId;
    if (workspaceProjectId != null) return workspaceProjectId;
    final selection = _client.selection.state;
    return selection.selectedThreadId == threadId
        ? selection.selectedProjectId
        : null;
  }

  bool _shouldActivateProject(String projectId) =>
      _executionBlocker(projectId: projectId) == null;

  void _setLoadMoreError(String? message) {
    if (state.loadMoreError == message) return;
    state = DirectoryCommandState(loadMoreError: message);
  }

  StudioTransport get _api => _client.transport;
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
