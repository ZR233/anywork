import 'dart:async';

import 'package:anywork_client/conversation.dart'
    show
        ConversationActivationFailure,
        StopExecutionResult,
        StopNoExecution,
        StopExecutionOperation;
import 'package:anywork_client/operations.dart';
import 'package:anywork_client/remote.dart';
import 'package:anywork_client/resources.dart';
import 'package:anywork_client/workspace.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../app/app_bindings.dart';
import '../state/agent_list_stop.dart';
import '../state/collection_presentation.dart';
import '../state/workspace_view_state.dart';

part 'workspace_view_model.g.dart';

@Riverpod(keepAlive: true)
class WorkspaceViewModel extends _$WorkspaceViewModel {
  final Map<String, Observation> _actions = {};
  final List<Observation> _observations = [];
  ThreadMetadata? _metadata;
  Observation? _metadataObservation;
  bool _alive = true;
  int _presentationIntent = 0;
  int _editorSerial = 0;
  int _navigationSerial = 0;
  int _projectReadSerial = 0;
  int _openSerial = 0;
  bool _initializing = false;

  WorkspaceRepository get _repository => ref.read(workspaceRepositoryProvider);

  @override
  FutureOr<WorkspaceViewState> build() {
    _alive = true;
    _initializing = true;
    ref.onDispose(_disposeBindings);
    try {
      final initial = _initialize();
      _initializing = false;
      return initial;
    } catch (error, stack) {
      _disposeBindings();
      Error.throwWithStackTrace(error, stack);
    }
  }

  WorkspaceViewState _initialize() {
    final repository = ref.watch(workspaceRepositoryProvider);
    final conversations = ref.watch(conversationRepositoryProvider);
    final selection = repository.state.watchLatest((workspace) {
      if (!_alive || _initializing) return;
      state = AsyncData(
        state.requireValue.copyWith(
          workspace: workspace,
          activationFailure: _matchingActivationFailure(
            conversations.activationFailure.value,
            workspace,
          ),
        ),
      );
      _bindMetadata(
        workspace.sealed || workspace.selection.needsOpen
            ? null
            : workspace.selection.threadId,
      );
      _bindProject();
    });
    _observations.add(selection.observation);
    final activation = conversations.activationFailure.watchLatest((failure) {
      if (!_alive || _initializing) return;
      // D1 owns this evidence. Filter using D3's latest canonical identity,
      // including A→B→A with a new selection generation.
      state = AsyncData(
        state.requireValue.copyWith(
          activationFailure: _matchingActivationFailure(
            failure,
            repository.state.value,
          ),
        ),
      );
    });
    _observations.add(activation.observation);
    final projects = repository.projects.watchLatest((projects) {
      if (!_alive || _initializing) return;
      state = AsyncData(state.requireValue.copyWith(projects: projects));
      _refreshProject();
    });
    _observations.add(projects.observation);
    final agents = repository.agents.watchLatest((agents) {
      if (_alive && !_initializing) {
        state = AsyncData(state.requireValue.copyWith(agents: agents));
      }
    });
    _observations.add(agents.observation);
    final currentSelection = repository.state.value;
    final initial = WorkspaceViewState(
      workspace: currentSelection,
      activationFailure: _matchingActivationFailure(
        conversations.activationFailure.value,
        currentSelection,
      ),
      projects: repository.projects.value,
      agents: repository.agents.value,
      selectedProject: presentRows(repository.projects.value.projects)
          .where(
            (project) => project.id == currentSelection.selection.projectId,
          )
          .firstOrNull,
      projectLoading: false,
      projectReadError: null,
      selectedMetadata: null,
      metadataDemandError: null,
      actions: const {},
      openResult: null,
      opening: false,
      openAdmissionError: null,
      navigation: null,
      nameEditor: null,
    );
    // Cold restoration is selection only. Even this read-only demand waits
    // until the canonical owner has accepted an explicit open.
    final threadId = currentSelection.selection.threadId;
    ThreadMetadataState? metadata;
    if (threadId != null &&
        !currentSelection.sealed &&
        !currentSelection.selection.needsOpen) {
      final borrowed = repository.thread(threadId);
      _metadata = borrowed;
      final watched = borrowed.state.watchLatest((value) {
        if (_alive && !_initializing && identical(_metadata, borrowed)) {
          state = AsyncData(
            state.requireValue.copyWith(selectedMetadata: value),
          );
        }
      });
      _metadataObservation = watched.observation;
      metadata = borrowed.state.value;
    }
    scheduleMicrotask(() {
      if (_alive) _bindProject();
    });
    return initial.copyWith(selectedMetadata: metadata);
  }

  ConversationActivationFailure? _matchingActivationFailure(
    ConversationActivationFailure? failure,
    WorkspaceState workspace,
  ) =>
      !workspace.sealed &&
          !workspace.selection.needsOpen &&
          failure?.threadId == workspace.selection.threadId &&
          failure?.selectionGeneration == workspace.selectionGeneration
      ? failure
      : null;

  /// Retry the rendered evidence, never a refreshed target or a new selection.
  void retryActivation(ConversationActivationFailure frozen) => ref
      .read(conversationRepositoryProvider)
      .retryActivation(
        threadId: frozen.threadId,
        selectionGeneration: frozen.selectionGeneration,
      );

  void _disposeBindings() {
    _alive = false;
    ++_projectReadSerial;
    ++_openSerial;
    for (final observation in [..._observations, ..._actions.values]) {
      observation.cancel();
    }
    _observations.clear();
    _actions.clear();
    _releaseMetadata();
  }

  void _bindMetadata(String? threadId) {
    if (threadId != null && _metadata?.threadId == threadId) return;
    _releaseMetadata();
    if (threadId == null) {
      state = AsyncData(
        state.requireValue.copyWith(
          selectedMetadata: null,
          metadataDemandError: null,
        ),
      );
      return;
    }
    state = AsyncData(
      state.requireValue.copyWith(
        selectedMetadata: null,
        metadataDemandError: null,
      ),
    );
    try {
      final borrowed = _repository.thread(threadId);
      _metadata = borrowed;
      final watched = borrowed.state.watchLatest((value) {
        if (!_alive || !identical(_metadata, borrowed)) return;
        state = AsyncData(state.requireValue.copyWith(selectedMetadata: value));
      });
      _metadataObservation = watched.observation;
      state = AsyncData(
        state.requireValue.copyWith(selectedMetadata: watched.value),
      );
    } on StudioFailure catch (error) {
      _releaseMetadata();
      state = AsyncData(
        state.requireValue.copyWith(metadataDemandError: error),
      );
    }
  }

  Future<void> retrySelectedMetadata() async {
    final workspace = state.requireValue.workspace;
    final selected = workspace.selection.threadId;
    if (workspace.sealed || workspace.selection.needsOpen || selected == null) {
      return;
    }
    final borrowed = _metadata;
    if (borrowed == null) {
      _bindMetadata(selected);
      return;
    }
    try {
      await borrowed.retry();
      if (_alive && identical(_metadata, borrowed)) {
        state = AsyncData(
          state.requireValue.copyWith(metadataDemandError: null),
        );
      }
    } on StudioFailure catch (error) {
      if (_alive && identical(_metadata, borrowed)) {
        state = AsyncData(
          state.requireValue.copyWith(metadataDemandError: error),
        );
      }
    }
  }

  /// Explicit retry of the canonical Project directory after a typed source
  /// failure. The notice owns the affordance; the window/source reads stay here.
  Future<void> retryProjectsSource() async {
    if (!_alive) return;
    if (state.requireValue.workspace.sealed) return;
    try {
      await _repository.loadProjectSourceStatus();
      await _repository.loadProjectsPage();
    } on StudioFailure {
      // The mirror republishes the typed failure; the banner stays visible.
    }
  }

  void _bindProject() {
    final value = state.requireValue;
    final id = value.workspace.selection.projectId;
    ++_projectReadSerial;
    final project =
        presentRows(value.projects.projects)
            .where((project) => project.id == id)
            .firstOrNull ??
        (value.selectedProject?.id == id ? value.selectedProject : null);
    state = AsyncData(
      value.copyWith(
        selectedProject: project,
        projectLoading: false,
        projectReadError: null,
      ),
    );
    if (id != null &&
        project == null &&
        !value.workspace.sealed &&
        !value.workspace.selection.needsOpen) {
      unawaited(loadSelectedProject());
    }
  }

  void _refreshProject() {
    final value = state.requireValue;
    final project = presentRows(value.projects.projects)
        .where((project) => project.id == value.workspace.selection.projectId)
        .firstOrNull;
    if (project == null) return; // A partial window is not a deletion.
    ++_projectReadSerial;
    state = AsyncData(
      value.copyWith(
        selectedProject: project,
        projectLoading: false,
        projectReadError: null,
      ),
    );
  }

  Future<void> loadSelectedProject() async {
    final value = state.requireValue;
    final id = value.workspace.selection.projectId;
    if (id == null ||
        value.workspace.sealed ||
        value.workspace.selection.needsOpen) {
      return;
    }
    final generation = value.workspace.selectionGeneration;
    final serial = ++_projectReadSerial;
    final repository = _repository;
    bool current() =>
        _alive &&
        serial == _projectReadSerial &&
        state.requireValue.workspace.selectionGeneration == generation &&
        state.requireValue.workspace.selection.projectId == id;
    state = AsyncData(
      value.copyWith(projectLoading: true, projectReadError: null),
    );
    try {
      // Single-entity read: the current Project window need not contain this ID.
      // This is presentation of the frozen read result, never a new selection.
      final project = await repository.readProject(id);
      if (current()) {
        state = AsyncData(
          state.requireValue.copyWith(
            selectedProject: project,
            projectLoading: false,
          ),
        );
      }
    } on StudioFailure catch (error) {
      if (current()) {
        state = AsyncData(
          state.requireValue.copyWith(
            projectLoading: false,
            projectReadError: error,
          ),
        );
      }
    }
  }

  void _releaseMetadata() {
    _metadataObservation?.cancel();
    _metadataObservation = null;
    final borrowed = _metadata;
    _metadata = null;
    if (borrowed == null) return;
    borrowed.requestClose();
    // Repository supervises this exact borrowed scope until true join. Closing
    // it never closes a Conversation Session or releases another observer.
    unawaited(borrowed.close().then<void>((_) {}, onError: _queryCloseError));
  }

  void _queryCloseError(Object error, StackTrace stack) {
    // Keep the original error in the application zone. Domain close still owns
    // the unresolved scope and will include it in application shutdown.
    Zone.current.handleUncaughtError(error, stack);
  }

  Future<CommandResult<WorkspaceSelectionResult>?> selectProject(String id) =>
      _run('selection', () => _repository.selectProject(id));
  Future<CommandResult<WorkspaceSelectionResult>?> selectThread(String id) =>
      _run('selection', () => _repository.selectThread(id));
  Future<CommandResult<WorkspaceSelectionResult>?> selectAgentThread(
    String id,
  ) => _run('selection', () => _repository.selectAgentThread(id));

  /// A cold navigation entry, not an open command or an application-owned
  /// selection. The existing observer presents the SDK's canonical result.
  WorkspaceSelectionResult restoreSelection(WorkspaceSelection selection) =>
      _repository.restoreSelection(selection);
  Future<CommandResult<WorkspaceSelectionResult>?> openSelectedThread(
    String id,
  ) => _run('open-thread:$id', () => _repository.openSelectedThread(id));
  Future<CommandResult<WorkspaceSelectionResult>?> beginNewThread(
    String projectId,
  ) => _run('selection', () => _repository.beginNewThread(projectId));
  Future<CommandResult<WorkspaceSelectionResult>?> restoreThread(String id) =>
      _run('restore-thread:$id', () => _repository.restoreThread(id));
  Future<CommandResult<Unit>?> archiveProject(String id) =>
      _run('project:$id', () => _repository.archiveProject(id));
  Future<CommandResult<ArchiveThreadResult>?> archiveThread(String id) =>
      _run('thread:$id', () => _repository.archiveThread(id));

  Future<CommandResult<Unit>?> stopDirectoryExecution(
    AgentDirectoryState directory,
    AgentDirectoryEntry agent,
  ) {
    if (!_alive || state.requireValue.workspace.sealed) {
      return Future.value();
    }
    // Capture the rendered Ready row synchronously, before publishing pending
    // or invoking any external callback. Never select/open the member here.
    final target = AgentListStopTarget.capture(directory, agent);
    if (target == null) return Future.value();
    final previous =
        state.requireValue.actions['directory-stop:${target.threadId}'];
    final pendingTarget = previous?.directoryStopTarget;
    if (previous?.waiting == true &&
        pendingTarget?.origin.origin == target.origin.origin &&
        pendingTarget?.member.entry == target.member.entry &&
        pendingTarget?.executionId == target.executionId) {
      // UI admission only: retain the original observation while its ticket is
      // in flight. Cross-observer deduplication remains the SDK's capability.
      return Future.value();
    }
    final conversations = ref.read(conversationRepositoryProvider);
    final StopExecutionResult admission;
    try {
      // The SDK makes this decision before a local pending presentation exists.
      // NoExecution neither registers an operation nor implies a successful stop.
      admission = conversations.stopDirectoryExecution(
        origin: target.origin,
        member: target.member,
        executionId: target.executionId,
      );
    } on StudioFailure catch (error) {
      // Invalid sources and different executions remain real rejections; only
      // the explicit sealed NoExecution branch is the benign zero-request race.
      if (_alive) {
        final key = 'directory-stop:${target.threadId}';
        _actions.remove(key)?.cancel();
        _setAction(
          key,
          WorkspaceActionPresentation(
            intent: ++_presentationIntent,
            waiting: false,
            operation: null,
            admissionError: error,
            directoryStopTarget: target,
          ),
        );
      }
      return Future.value();
    }
    return switch (admission) {
      StopNoExecution() => Future.value(),
      StopExecutionOperation(:final ticket) => _run(
        'directory-stop:${target.threadId}',
        () => ticket,
        directoryStopTarget: target,
      ),
    };
  }

  Future<void> openProject(String path) =>
      _open(() => _repository.openProject(path));
  Future<void> openRemoteProject(String alias, String path, {String? name}) =>
      _open(() => _repository.openRemoteProject(alias, path, name: name));

  Future<bool> hasRemoteHost(String alias) async {
    final remote = ref.read(remoteRepositoryProvider);
    final result = await remote.reloadServers().result;
    final servers = switch (result) {
      CommittedCommandResult<List<SshServerRuntimeEntry>>(:final value) ||
      AcknowledgedCommandResult<List<SshServerRuntimeEntry>>(
        :final value,
      ) => value,
      RejectedCommandResult(:final error) ||
      UnknownOutcomeCommandResult(:final error) ||
      SyncFailedCommandResult(:final error) ||
      AcknowledgedSyncFailedCommandResult(:final error) => throw error,
    };
    return servers.any((server) => server.profile.alias == alias);
  }

  void dismissOpenResult() {
    state = AsyncData(
      state.requireValue.copyWith(openResult: null, openAdmissionError: null),
    );
  }

  Future<void> _open(WorkspaceOpenBatch Function() create) async {
    final previous = state.requireValue;
    if (previous.opening || previous.workspace.sealed) return;
    final serial = ++_openSerial;
    state = AsyncData(
      previous.copyWith(
        opening: true,
        openResult: null,
        openAdmissionError: null,
      ),
    );
    try {
      final batch = create();
      final result = await batch.result;
      if (!_alive || serial != _openSerial) return;
      // Preserve each successful native step even when activation/navigation
      // failed or was superseded. No boolean collapses this batch.
      state = AsyncData(
        state.requireValue.copyWith(opening: false, openResult: result),
      );
    } on StudioFailure catch (error) {
      if (_alive && serial == _openSerial) {
        state = AsyncData(
          state.requireValue.copyWith(
            opening: false,
            openAdmissionError: error,
          ),
        );
      }
    }
  }

  Future<CommandResult<T>?> _run<T>(
    String key,
    OperationTicket<T> Function() create, {
    AgentListStopTarget? directoryStopTarget,
  }) async {
    final previous = state.requireValue;
    if (previous.workspace.sealed) return null;
    // New selection intents must reach D3 even while an older selection is
    // pending (including A→B→A). Other target-conflicting UI writes are gated.
    if (key != 'selection' &&
        directoryStopTarget == null &&
        previous.actions[key]?.waiting == true) {
      return null;
    }
    final intent = ++_presentationIntent;
    _actions.remove(key)?.cancel();
    _setAction(
      key,
      WorkspaceActionPresentation(
        intent: intent,
        waiting: true,
        operation: null,
        admissionError: null,
        directoryStopTarget: directoryStopTarget,
      ),
    );
    if (!_currentAction(key, intent)) return null;
    try {
      // Directory stops share the SDK's ticket/deduplication; this VM owns only
      // a presentation observation, not another stop queue or replay policy.
      final ticket = create();
      try {
        final watched = ticket.state.watchLatest((operation) {
          if (!_currentAction(key, intent)) return;
          _setAction(
            key,
            state.requireValue.actions[key]!.copyWith(operation: operation),
          );
        });
        if (_currentAction(key, intent)) {
          _actions[key] = watched.observation;
          _setAction(
            key,
            state.requireValue.actions[key]!.copyWith(operation: watched.value),
          );
        } else {
          watched.observation.cancel();
        }
      } on StudioFailure catch (error) {
        if (_currentAction(key, intent)) {
          _setAction(
            key,
            state.requireValue.actions[key]!.copyWith(
              observationError: error,
              operation: ticket.state.value,
            ),
          );
        }
      }
      // Observation budget failure does not reject or discard an admitted
      // ticket. Always await its original typed outcome; never replay it.
      final result = await ticket.result;
      if (_currentAction(key, intent)) {
        _setAction(
          key,
          state.requireValue.actions[key]!.copyWith(
            waiting: false,
            operation: ticket.state.value,
          ),
        );
      }
      return result;
    } on StudioFailure catch (error) {
      if (_currentAction(key, intent)) {
        _setAction(
          key,
          state.requireValue.actions[key]!.copyWith(
            waiting: false,
            admissionError: error,
          ),
        );
      }
      return null;
    }
  }

  bool _currentAction(String key, int intent) =>
      _alive && state.requireValue.actions[key]?.intent == intent;

  void _setAction(String key, WorkspaceActionPresentation action) {
    state = AsyncData(
      state.requireValue.copyWith(
        actions: {...state.requireValue.actions, key: action},
      ),
    );
  }

  void navigate(WorkspaceNavigationDestination destination) {
    if (state.requireValue.workspace.sealed) return;
    state = AsyncData(
      state.requireValue.copyWith(
        navigation: WorkspaceNavigationIntent(
          serial: ++_navigationSerial,
          destination: destination,
        ),
      ),
    );
  }

  int editThreadName(WorkspaceThreadRecord thread) =>
      _editName(WorkspaceNameTarget.thread, thread.id, thread.title);
  int editProjectName(ProjectRecord project) =>
      _editName(WorkspaceNameTarget.project, project.id, project.name);

  int _editName(WorkspaceNameTarget target, String id, String raw) {
    final serial = ++_editorSerial;
    state = AsyncData(
      state.requireValue.copyWith(
        nameEditor: WorkspaceNameEditor(
          serial: serial,
          target: target,
          id: id,
          raw: raw,
          problem: null,
          saving: false,
          error: null,
        ),
      ),
    );
    return serial;
  }

  void changeName(String raw) {
    final editor = state.requireValue.nameEditor;
    if (editor == null) return;
    state = AsyncData(
      state.requireValue.copyWith(
        nameEditor: editor.copyWith(
          raw: raw,
          problem: _nameProblem(editor.target, raw),
          error: null,
        ),
      ),
    );
  }

  WorkspaceNameProblem? _nameProblem(WorkspaceNameTarget target, String raw) {
    final name = raw.trim();
    if (name.isEmpty) return WorkspaceNameProblem.empty;
    if (target == WorkspaceNameTarget.thread && name.runes.length > 80) {
      return WorkspaceNameProblem.tooLong;
    }
    return null;
  }

  void cancelNameEditor(int expectedSerial) {
    if (!_alive || state.requireValue.nameEditor?.serial != expectedSerial) {
      return;
    }
    state = AsyncData(state.requireValue.copyWith(nameEditor: null));
  }

  Future<bool> saveName() async {
    final editor = state.requireValue.nameEditor;
    if (editor == null || editor.saving) return false;
    final problem = _nameProblem(editor.target, editor.raw);
    if (problem != null) {
      state = AsyncData(
        state.requireValue.copyWith(
          nameEditor: editor.copyWith(problem: problem),
        ),
      );
      return false;
    }
    state = AsyncData(
      state.requireValue.copyWith(
        nameEditor: editor.copyWith(saving: true, error: null),
      ),
    );
    final success = switch (editor.target) {
      WorkspaceNameTarget.project => _succeeded(
        await _run(
          'project:${editor.id}',
          () => _repository.renameProject(editor.id, editor.raw.trim()),
        ),
      ),
      WorkspaceNameTarget.thread => _succeeded(
        await _run(
          'thread:${editor.id}',
          () => _repository.renameThread(editor.id, editor.raw.trim()),
        ),
      ),
    };
    if (!_alive) return false;
    final current = state.requireValue.nameEditor;
    if (current?.serial != editor.serial) return false;
    if (success && current!.raw == editor.raw) {
      state = AsyncData(state.requireValue.copyWith(nameEditor: null));
      return true;
    }
    final actionKey = '${editor.target.name}:${editor.id}';
    final action = state.requireValue.actions[actionKey];
    state = AsyncData(
      state.requireValue.copyWith(
        nameEditor: current!.copyWith(
          saving: false,
          error: action?.admissionError ?? action?.operation?.error,
        ),
      ),
    );
    return false;
  }

  bool _succeeded<T>(CommandResult<T>? result) =>
      result is CommittedCommandResult<T> ||
      result is AcknowledgedCommandResult<T>;
}
