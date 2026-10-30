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
  int _standalonePreparationGeneration = 0;

  Future<void> close() {
    _lane.seal();
    return _lane.join();
  }

  Future<void> openProject(String path) {
    return _navigate((intent) async {
      _throwIfAccessBlocked(workspaceId: null);
      final project = await _api.openProject(path);
      if (!_ownsNavigation(intent)) return;
      _throwIfAccessBlocked(workspaceId: project.id);
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
    _setStandalonePreparation(isPreparing: false, error: null);
    return _lane.enqueue(() async {
      if (!_ownsNavigation(intent)) return false;
      try {
        _throwIfAccessBlocked(workspaceId: null);
        var project = await _api.openRemoteProject(alias, path);
        if (!_ownsNavigation(intent)) return false;
        _throwIfAccessBlocked(workspaceId: project.id);
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

  Future<void> selectProject(String workspaceId) {
    return _navigate((intent) async {
      _throwIfAccessBlocked(workspaceId: workspaceId);
      if (_client.selection.state.selectedProjectId == workspaceId) {
        return;
      }
      if (_shouldActivateProject(workspaceId)) {
        await _api.activateProject(workspaceId);
      }
      if (!_ownsNavigation(intent)) return;
      _selectProjectDefault(workspaceId);
    });
  }

  Future<void> selectThread(String threadId) {
    return _navigate((_) async {
      final thread = _directoryThread(threadId);
      if (thread == null) return;
      _throwIfAccessBlocked(workspaceId: thread.workspaceId, threadId: threadId);
      final selection = _client.selection.state;
      if (selection.selectedThreadId == threadId) {
        _client.selection.markOpened();
        return;
      }
      _client.selection.selectThread(
        workspaceId: thread.workspaceId,
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
      workspaceId: selected.selectedProjectId,
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
        workspaceId: selected.selectedProjectId,
        threadId: threadId,
      );
      if (!isCurrent()) return;
      if (target.id != threadId ||
          target.effectiveRootThreadId != root ||
          target.workspaceId != selected.selectedProjectId) {
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
        target.workspaceId != selected.selectedProjectId)
      return;
    _throwIfAccessBlocked(workspaceId: target.workspaceId, threadId: threadId);
    _client.selection.selectThread(
      workspaceId: target.workspaceId,
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
        workspaceId: selection.selectedProjectId,
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
  Future<void> beginNewThread({String? workspaceId}) {
    return _navigate((intent) async {
      final target = workspaceId ?? _client.selection.state.selectedProjectId;
      if (target == null) return;
      _throwIfAccessBlocked(workspaceId: target);
      if (_client.selection.state.selectedProjectId != target) {
        if (_shouldActivateProject(target)) {
          await _api.activateProject(target);
          if (!_ownsNavigation(intent)) return;
        }
      }
      _client.selection.selectProject(target);
    });
  }

  /// Prepare the canonical standalone owner and select it as a new-thread
  /// target. This never creates a Thread; submission remains owned by drafts.
  Future<void> beginStandaloneThread() {
    final preparation = ++_standalonePreparationGeneration;
    return _navigate(
      (intent) async {
        try {
          _throwIfAccessBlocked(workspaceId: null);
          final directory = await _api.prepareStandaloneWorkspace();
          if (_client.project.applyProjectDirectory(directory)) {
            _client.reconcileSelectedProject();
          }
          if (!_ownsNavigation(intent)) return;
          final standaloneProjects =
              (_client.project.state.projects?.values ??
                      const <StudioProject>[])
                  .where((project) => project.isStandalone)
                  .toList(growable: false);
          if (standaloneProjects.length != 1) {
            throw const StudioFailure(
              code: StudioFailureCode.protocol,
              message: 'Project directory must contain exactly one standalone workspace',
              retryable: false,
              correlationId: 'client-standalone-workspace',
            );
          }
          final project = standaloneProjects.single;
          _throwIfAccessBlocked(workspaceId: project.id);
          if (_shouldActivateProject(project.id)) {
            await _api.activateProject(project.id);
          }
          if (!_ownsNavigation(intent)) return;
          _client.drafts.startDraft.setWorkspaceMode(
            project.id,
            ThreadWorkspaceMode.local,
          );
          _setStandalonePreparation(isPreparing: false, error: null);
          _client.selection.selectProject(project.id);
        } catch (error) {
          if (_ownsNavigation(intent)) {
            _setStandalonePreparation(
              isPreparing: false,
              error: error.toString(),
            );
          }
          rethrow;
        }
      },
      standalonePreparation: true,
      preparationGeneration: preparation,
    );
  }

  Future<void> restoreThread(String threadId) {
    return _navigate((intent) async {
      _throwIfAccessBlocked(
        workspaceId: _workspaceIdForThread(threadId),
        threadId: threadId,
      );
      final thread = await _api.restoreThread(threadId);
      if (!_ownsNavigation(intent)) return;
      _throwIfAccessBlocked(workspaceId: thread.workspaceId, threadId: thread.id);
      _client.selection.selectThread(
        workspaceId: thread.workspaceId,
        threadId: thread.id,
      );
    });
  }

  Future<void> archiveProject(String workspaceId) {
    if (_client.selection.state.selectedProjectId == workspaceId) {
      _client.selection.beginNavigation();
    }
    return _lane.enqueue(() async {
      if (_selectedProjectBusy(workspaceId)) return;
      // 只记录当前已加载窗口中的该项目会话。分页窗口之外的 id 不能当成已删除。
      final loadedIds = _client.threadDirectory.state.window.threads
          .where((thread) => thread.workspaceId == workspaceId)
          .map((thread) => thread.id)
          .toSet();
      // Capture logical draft owners before directory removal can arrive.
      final draftOwners = _client.drafts.projectComposers(workspaceId);
      await _api.archiveProject(workspaceId);
      if (_client.isClosed) return;
      await _client.drafts.discardProjectDrafts(workspaceId, draftOwners);
      for (final id in loadedIds) {
        if (_client.selection.state.selectedThreadId == id) {
          _client.conversations.setVisibleThread(null);
        }
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
    final workspaceId = _client.selection.state.selectedProjectId;
    if (workspaceId == null) return;
    final snapshot = await _api.readSkillsState(workspaceId);
    if (_client.isClosed) return;
    _client.skills(workspaceId).apply(snapshot);
  });

  Future<List<String>> discoverSkills() => _lane.run(() async {
    final workspaceId = _client.selection.state.selectedProjectId;
    if (workspaceId == null) return const [];
    final snapshot = await _api.discoverSkills(workspaceId);
    if (!_client.isClosed) {
      _client.skills(workspaceId).apply(snapshot);
    }
    return snapshot.skills;
  });

  Future<SkillSearchResultView?> searchSkills(String query, {int limit = 50}) =>
      _lane.run(() async {
        final workspaceId = _client.selection.state.selectedProjectId;
        if (workspaceId == null) return null;
        return _api.searchSkills(workspaceId, query, limit: limit);
      });

  Future<void> refreshMcpState() => _applyMcp(_api.readMcpState);

  Future<void> resetMcpServer(String serverId) =>
      _applyMcp(() => _api.resetMcpServer(serverId));

  Future<void> resetAllMcp() => _applyMcp(_api.resetAllMcp);

  Future<void> refreshLspState() => _applyLsp(_api.readLspState);

  Future<void> probeLspServer() => _lane.run(() async {
    final workspaceId = _client.selection.state.selectedProjectId;
    if (workspaceId == null) return;
    await _applyLsp(() => _api.probeLspServer(workspaceId));
  });

  Future<void> repairLspServer(String serverId) => _lane.run(() async {
    final workspaceId = _client.selection.state.selectedProjectId;
    if (workspaceId == null) return;
    await _applyLsp(() => _api.repairLspServer(workspaceId, serverId));
  });

  Future<void> resetLspServer(String serverId) => _lane.run(() async {
    final workspaceId = _client.selection.state.selectedProjectId;
    if (workspaceId == null) return;
    await _applyLsp(() => _api.resetLspServer(workspaceId, serverId));
  });

  Future<void> resetLspWorkspace() => _lane.run(() async {
    final workspaceId = _client.selection.state.selectedProjectId;
    if (workspaceId == null) return;
    await _applyLsp(() => _api.resetLspWorkspace(workspaceId));
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
      workspaceId: _workspaceIdForThread(threadId),
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

  Future<void> _navigate(
    Future<void> Function(int intent) action, {
    bool standalonePreparation = false,
    int? preparationGeneration,
  }) {
    final intent = _client.selection.beginNavigation();
    _setStandalonePreparation(isPreparing: standalonePreparation, error: null);
    return _lane.enqueue(() async {
      try {
        if (!_ownsNavigation(intent)) return;
        try {
          await action(intent);
        } catch (_) {
          // Current failures stay visible. A superseded read must not deliver a
          // stale error to the menu after a newer navigation has been accepted.
          if (_ownsNavigation(intent)) rethrow;
        }
      } finally {
        if (preparationGeneration != null &&
            preparationGeneration == _standalonePreparationGeneration &&
            state.standalonePreparationInProgress) {
          _setStandalonePreparation(
            isPreparing: false,
            error: state.standalonePreparationError,
          );
        }
      }
    });
  }

  void _selectProjectDefault(String workspaceId) {
    final threadId = _client.threadDirectory.state.window.threads
        .where(
          (thread) =>
              thread.isRoot &&
              thread.workspaceId == workspaceId &&
              _accessBlocker(
                    workspaceId: thread.workspaceId,
                    threadId: thread.id,
                  ) ==
                  null,
        )
        .firstOrNull
        ?.id;
    if (threadId == null) {
      _client.selection.selectProject(workspaceId);
    } else {
      _client.selection.selectThread(workspaceId: workspaceId, threadId: threadId);
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

  bool _selectedProjectBusy(String workspaceId) {
    final selection = _client.selection.state;
    if (selection.selectedProjectId != workspaceId) return false;
    final threadId = selection.selectedThreadId;
    if (threadId == null) return false;
    return _client.conversations
            .session(threadId)
            .state
            .activeTurn
            ?.state
            .isBusy ??
        false;
  }

  StudioRecoveryIssue? _accessBlocker({
    required String? workspaceId,
    String? threadId,
  }) => recoveryIssueBlockingAccess(
    _client.recovery.state.value?.values ?? const [],
    workspaceId: workspaceId,
    threadId: threadId,
  );

  StudioRecoveryIssue? _executionBlocker({
    required String? workspaceId,
    String? threadId,
  }) => recoveryIssueBlockingExecution(
    _client.recovery.state.value?.values ?? const [],
    workspaceId: workspaceId,
    threadId: threadId,
  );

  void _throwIfAccessBlocked({required String? workspaceId, String? threadId}) {
    final issue = _accessBlocker(workspaceId: workspaceId, threadId: threadId);
    if (issue != null) throw issue.blockedFailure();
  }

  void _throwIfExecutionBlocked({
    required String? workspaceId,
    String? threadId,
  }) {
    final issue = _executionBlocker(workspaceId: workspaceId, threadId: threadId);
    if (issue != null) throw issue.blockedFailure();
  }

  String? _workspaceIdForThread(String threadId) {
    final directoryProjectId = _directoryThread(threadId)?.workspaceId;
    if (directoryProjectId != null) return directoryProjectId;
    final workspaceProjectId = _client.conversations
        .sessionState(threadId)
        ?.workspace
        ?.thread
        .workspaceId;
    if (workspaceProjectId != null) return workspaceProjectId;
    final selection = _client.selection.state;
    return selection.selectedThreadId == threadId
        ? selection.selectedProjectId
        : null;
  }

  bool _shouldActivateProject(String workspaceId) =>
      _executionBlocker(workspaceId: workspaceId) == null;

  void _setLoadMoreError(String? message) {
    if (state.loadMoreError == message) return;
    state = state.copyWith(loadMoreError: message);
  }

  void _setStandalonePreparation({
    required bool isPreparing,
    required String? error,
  }) {
    if (state.standalonePreparationInProgress == isPreparing &&
        state.standalonePreparationError == error) {
      return;
    }
    state = state.copyWith(
      standalonePreparationInProgress: isPreparing,
      standalonePreparationError: error,
    );
  }

  StudioTransport get _api => _client.transport;
}

class DirectoryCommandState {
  const DirectoryCommandState({
    this.loadMoreError,
    this.standalonePreparationInProgress = false,
    this.standalonePreparationError,
  });

  final String? loadMoreError;
  final bool standalonePreparationInProgress;
  final String? standalonePreparationError;

  DirectoryCommandState copyWith({
    Object? loadMoreError = _directoryCommandUnchanged,
    bool? standalonePreparationInProgress,
    Object? standalonePreparationError = _directoryCommandUnchanged,
  }) => DirectoryCommandState(
    loadMoreError: identical(loadMoreError, _directoryCommandUnchanged)
        ? this.loadMoreError
        : loadMoreError as String?,
    standalonePreparationInProgress:
        standalonePreparationInProgress ?? this.standalonePreparationInProgress,
    standalonePreparationError:
        identical(standalonePreparationError, _directoryCommandUnchanged)
        ? this.standalonePreparationError
        : standalonePreparationError as String?,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DirectoryCommandState &&
          loadMoreError == other.loadMoreError &&
          standalonePreparationInProgress ==
              other.standalonePreparationInProgress &&
          standalonePreparationError == other.standalonePreparationError;

  @override
  int get hashCode => Object.hash(
    loadMoreError,
    standalonePreparationInProgress,
    standalonePreparationError,
  );
}

const _directoryCommandUnchanged = Object();
