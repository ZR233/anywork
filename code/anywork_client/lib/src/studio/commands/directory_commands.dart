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
      await _selectProjectDefault(project.id);
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
        await _selectProjectDefault(project.id);
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
      await _selectProjectDefault(workspaceId);
    });
  }

  Future<void> selectThread(String threadId) {
    return _navigate((_) async {
      final thread = await _requireThread(threadId);
      _throwIfAccessBlocked(
        workspaceId: thread.workspaceId,
        threadId: threadId,
      );
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
    final selectedId = selected.selectedThreadId;
    final selectedThread = selectedId == null
        ? null
        : await _readThread(selectedId);
    if (!_ownsNavigation(intent) ||
        !identical(_client.selection.state, selected)) {
      return;
    }
    final root = AgentDirectoryQueries.rootThreadId(
      threadId: selectedId,
      agents: _client.project.state.agents?.values ?? const [],
      threads: [if (selectedThread != null) selectedThread],
    );
    if (root == null ||
        !_rootMembers(root).any((agent) => agent.threadId == threadId)) {
      return;
    }
    bool isCurrent() =>
        _ownsNavigation(intent) &&
        identical(_client.selection.state, selected) &&
        _rootMembers(root).any((agent) => agent.threadId == threadId);
    final target = await _requireThread(threadId);
    if (!isCurrent()) return;
    _throwIfAccessBlocked(
      workspaceId: selected.selectedProjectId,
      threadId: threadId,
    );
    if (target.effectiveRootThreadId != root ||
        target.workspaceId != selected.selectedProjectId) {
      throw const StudioFailure(
        code: StudioFailureCode.protocol,
        message: 'Selected agent metadata did not match its canonical root',
        retryable: false,
        correlationId: 'client-select-agent',
      );
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
      await _requireThread(threadId);
      if (!_ownsNavigation(intent)) return;
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
      final existing = await _readThread(threadId);
      _throwIfAccessBlocked(
        workspaceId: _workspaceIdForThread(threadId, existing),
        threadId: threadId,
      );
      final thread = await _api.restoreThread(threadId);
      if (!_ownsNavigation(intent)) return;
      _throwIfAccessBlocked(
        workspaceId: thread.workspaceId,
        threadId: thread.id,
      );
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
      // Capture logical draft owners before directory removal can arrive.
      final draftOwners = _client.drafts.projectComposers(workspaceId);
      await _api.archiveProject(workspaceId);
      if (_client.isClosed) return;
      await _client.drafts.discardProjectDrafts(workspaceId, draftOwners);
      if (_client.selection.state.selectedProjectId == workspaceId) {
        _client.conversations.setVisibleThread(null);
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

  Future<McpCatalogSnapshot> readMcpCatalog([
    McpScope scope = const McpScope.host(),
  ]) => _applyMcpCatalog(scope, () => _api.readMcpCatalog(scope));

  Future<McpCatalogSnapshot> reloadMcpCatalog([
    McpScope scope = const McpScope.host(),
  ]) => _applyMcpCatalog(scope, () => _api.reloadMcpCatalog(scope));

  Future<McpDocumentContent> readMcpDocument(McpDocumentRef document) =>
      _lane.run(() => _api.readMcpDocument(document));

  Future<McpDocumentCommitReceipt> createMcpDocument({
    required McpScope scope,
    required String id,
    required String rawToml,
  }) => _lane.run(() async {
    final receipt = await _api.createMcpDocument(
      scope: scope,
      id: id,
      rawToml: rawToml,
    );
    if (!_client.isClosed) {
      _client.mcpCatalog(receipt.snapshot.scope).apply(receipt.snapshot);
    }
    return receipt;
  });

  Future<McpDocumentCommitReceipt> updateMcpDocument({
    required McpDocumentRef document,
    required int expectedRevision,
    required String rawToml,
  }) => _lane.run(() async {
    final receipt = await _api.updateMcpDocument(
      document: document,
      expectedRevision: expectedRevision,
      rawToml: rawToml,
    );
    if (!_client.isClosed) {
      _client.mcpCatalog(receipt.snapshot.scope).apply(receipt.snapshot);
    }
    return receipt;
  });

  Future<McpDocumentCommitReceipt> deleteMcpDocument({
    required McpDocumentRef document,
    required int expectedRevision,
  }) => _lane.run(() async {
    final receipt = await _api.deleteMcpDocument(
      document: document,
      expectedRevision: expectedRevision,
    );
    if (!_client.isClosed) {
      _client.mcpCatalog(receipt.snapshot.scope).apply(receipt.snapshot);
    }
    return receipt;
  });

  Future<ThreadMcpStateSnapshot> readThreadMcp(String threadId) =>
      _applyThreadMcp(threadId, () => _api.readThreadMcp(threadId));

  Future<ThreadMcpStateSnapshot> reconnectThreadMcp({
    required String threadId,
    String? serverId,
  }) => _applyThreadMcp(
    threadId,
    () => _api.reconnectThreadMcp(threadId: threadId, serverId: serverId),
  );

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
    final thread = await _readThread(threadId);
    _throwIfExecutionBlocked(
      workspaceId: _workspaceIdForThread(threadId, thread),
      threadId: threadId,
    );
    return _api.resumeThreadHistory(threadId, faultGeneration);
  });

  Future<McpCatalogSnapshot> _applyMcpCatalog(
    McpScope scope,
    Future<McpCatalogSnapshot> Function() command,
  ) => _lane.run(() async {
    final snapshot = await command();
    if (!_client.isClosed) {
      _client.mcpCatalog(scope).apply(snapshot);
    }
    return snapshot;
  });

  Future<ThreadMcpStateSnapshot> _applyThreadMcp(
    String threadId,
    Future<ThreadMcpStateSnapshot> Function() command,
  ) => _lane.run(() async {
    final snapshot = await command();
    if (!_client.isClosed) {
      _client.threadMcp(threadId).apply(snapshot);
    }
    return snapshot;
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

  Future<void> _selectProjectDefault(String workspaceId) async {
    final frame = await _readThreads(
      DirectoryQuery(workspaceId: workspaceId),
      DirectoryWindow(),
    );
    final threadId = frame.threads
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
      _client.selection.selectThread(
        workspaceId: workspaceId,
        threadId: threadId,
      );
    }
  }

  List<StudioAgentView> _rootMembers(String rootId) =>
      AgentDirectoryQueries.forRoot(
        rootThreadId: rootId,
        agents: _client.project.state.agents?.values ?? const [],
      );

  Future<StudioThread?> _readThread(String threadId) async {
    final observation = _client.threadDirectory.observeThread(threadId);
    try {
      var state = observation.state.value;
      if (state.isLoading) {
        state = await observation.state.waitFor((value) => !value.isLoading);
      }
      if (state.error case final error?) throw error;
      return state.frame?.thread;
    } finally {
      await observation.release();
    }
  }

  Future<StudioThread> _requireThread(String threadId) async {
    final thread = await _readThread(threadId);
    if (thread != null) return thread;
    throw StudioFailure(
      code: StudioFailureCode.notFound,
      message: 'Thread metadata is unavailable: $threadId',
      retryable: false,
      correlationId: 'client-thread-metadata',
    );
  }

  Future<ThreadDirectoryFrame> _readThreads(
    DirectoryQuery query,
    DirectoryWindow window,
  ) async {
    final observation = _client.threadDirectory.observeThreads(query, window);
    try {
      var state = observation.state.value;
      if (state.isLoading) {
        state = await observation.state.waitFor((value) => !value.isLoading);
      }
      if (state.error case final error?) throw error;
      final frame = state.frame;
      if (frame == null) {
        throw StateError('Directory observation closed without a frame');
      }
      return frame;
    } finally {
      await observation.release();
    }
  }

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
    final issue = _executionBlocker(
      workspaceId: workspaceId,
      threadId: threadId,
    );
    if (issue != null) throw issue.blockedFailure();
  }

  String? _workspaceIdForThread(String threadId, StudioThread? metadata) {
    final directoryProjectId = metadata?.workspaceId;
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
