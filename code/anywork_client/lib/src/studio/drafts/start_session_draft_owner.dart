import 'dart:async';

import '../../../anywork_client.dart';
import '../../../models.dart';
import '../anywork_client.dart';
import '../model_route_queries.dart';
import 'submission_observation.dart';

/// Project drafts and mode-specific route intent survive route observers.
class StartSessionDraftOwner extends ReadModel<StartSessionDraft> {
  StartSessionDraftOwner(this._client) : super(const StartSessionDraft());

  final AnyworkClient _client;
  final Map<String, ResourcePermit> _permits = {};
  final List<Observation> _observations = [];
  final Map<String, (DraftStamp, DraftStamp)> _unknown = {};
  Future<bool>? _pending;
  Future<void>? _closing;
  bool _closed = false;

  void updateDraft(String projectId, String text) {
    final project = state.forProject(projectId);
    if (project.text == text && state.projects.containsKey(projectId)) return;
    _editProject(projectId, project.copyWith(text: text));
  }

  void setMode(String projectId, ThreadModeId mode) {
    final project = state.forProject(projectId);
    if (project.mode == mode && state.projects.containsKey(projectId)) return;
    _editProject(projectId, project.copyWith(mode: mode));
  }

  void setWorkspaceMode(String projectId, ThreadWorkspaceMode mode) {
    final project = state.forProject(projectId);
    if (project.workspaceMode == mode && state.projects.containsKey(projectId))
      return;
    _editProject(projectId, project.copyWith(workspaceMode: mode));
  }

  void setDelegationModeOverride(String projectId, DelegationMode? mode) {
    final project = state.forProject(projectId);
    if (project.delegationModeOverride == mode) return;
    _editProject(projectId, project.copyWith(delegationModeOverride: mode));
  }

  void setDelegationPreferenceOverride(
    String projectId,
    DelegationPreference? preference,
  ) {
    final project = state.forProject(projectId);
    if (project.delegationPreferenceOverride == preference) return;
    _editProject(
      projectId,
      project.copyWith(delegationPreferenceOverride: preference),
    );
  }

  void _editProject(String projectId, StartSessionProjectDraft project) {
    if (_closed) return;
    _reserve(projectId);
    state = state.copyWith(
      projects: {...state.projects, projectId: project},
      revision: state.revision + 1,
    );
  }

  void setModelIntent(ThreadModeId mode, String accountId, String modelId) {
    if (_closed || accountId.isEmpty || modelId.isEmpty) return;
    final next = StartSessionModelIntent(
      accountId: accountId,
      modelId: modelId,
    );
    final previous = state.modelIntents[mode.id];
    if (next == previous) return;
    final snapshot = _client.settings.state.canonical;
    final canonical = ModelRouteQueries.modeRoute(
      snapshot?.modeModelRoutes ?? const [],
      mode,
    );
    final changed = previous != null
        ? previous != next
        : canonical?.accountId != accountId || canonical?.modelId != modelId;
    final efforts = {...state.effortIntents};
    if (changed) {
      final effort = ModelRouteQueries.effortAfterModelSelection(
        ModelRouteQueries.model(
          snapshot?.accounts ?? const [],
          accountId,
          modelId,
        ),
        null,
      );
      if (effort != null && effort.isNotEmpty) {
        efforts[mode.id] = effort;
      } else {
        efforts.remove(mode.id);
      }
    }
    state = state.copyWith(
      modelIntents: {...state.modelIntents, mode.id: next},
      effortIntents: efforts,
      revision: state.revision + 1,
    );
  }

  void setEffortIntent(ThreadModeId mode, String effort) {
    if (_closed || effort.isEmpty || state.effortIntents[mode.id] == effort)
      return;
    state = state.copyWith(
      effortIntents: {...state.effortIntents, mode.id: effort},
      revision: state.revision + 1,
    );
  }

  /// Synchronous freeze: no queued settings write or later cache read may
  /// change the project, mode, route, text or attachment IDs sent by this call.
  FrozenStartSessionSubmission _freezeForSubmit(String projectId) {
    if (_closed || _client.isClosed)
      throw StateError('The start draft is closed');
    if (_pending != null)
      throw StateError('A start submission is already pending');
    final selection = _client.selection.state;
    if (selection.selectedProjectId != projectId ||
        selection.selectedThreadId != null) {
      throw StateError('New Thread submission target is no longer available');
    }
    final projects =
        _client.project.state.projects?.values ?? const <StudioProject>[];
    if (!projects.any((project) => project.id == projectId)) {
      throw StateError('Project is no longer available');
    }
    final blocked =
        _client.recovery.state.value?.values.any(
          (issue) =>
              issue.blocksAccess &&
              issue.scope == RecoveryIssueScope.project &&
              issue.projectId == projectId,
        ) ??
        false;
    if (blocked) throw StateError('Project submission is blocked by recovery');
    final project = state.forProject(projectId);
    final composer = _client.attachments.state.newThread(projectId);
    if (project.text.trim().isEmpty && composer.attachments.isEmpty) {
      throw StateError('Cannot submit an empty draft');
    }
    _reserve(projectId);
    final stamp = DraftStamp(
      draftId: 'start:$projectId',
      revision: state.revision,
    );
    final attachmentStamp = _client.attachments.newThreadStamp(projectId);
    if (_unknown[projectId] == (stamp, attachmentStamp)) {
      throw StateError('The previous submission outcome is unknown');
    }
    final route = resolveRoute(project.mode);
    final defaults = _client.settings.state.canonical!.delegation;
    final delegation = project.resolveDelegation(defaults);
    final operation = _client.mutations.begin(
      target: 'start:$projectId',
      draft: stamp,
    );
    final input = StudioPromptInput(
      inputId: operation.id.value,
      text: project.text.trim(),
      attachmentDraftIds: List.unmodifiable(
        composer.attachments.map((item) => item.id),
      ),
    );
    try {
      _client.attachments.retainFrozen(
        operationId: operation.id,
        binding: _client.attachments.newThreadBinding(projectId),
        attachmentIds: input.attachmentDraftIds,
      );
    } catch (error) {
      operation.reject(error);
      rethrow;
    }
    return FrozenStartSessionSubmission(
      stamp: stamp,
      attachmentStamp: attachmentStamp,
      operation: operation,
      projectId: projectId,
      project: project,
      route: route,
      delegation: delegation,
      input: input,
    );
  }

  Future<bool> submit(String projectId) {
    if (_pending != null) return Future<bool>.value(false);
    final FrozenStartSessionSubmission frozen;
    try {
      frozen = _freezeForSubmit(projectId);
    } catch (error) {
      _client.attachments.reportNewThreadFailure(projectId, error);
      return Future<bool>.value(false);
    }
    final completion = Completer<bool>();
    late final Future<bool> pending;
    pending = completion.future.whenComplete(() {
      if (identical(_pending, pending)) {
        _pending = null;
        if (!_closed) state = state.copyWith(submitting: false);
      }
    });
    // Publish ownership before notifying synchronous observers or starting transport work.
    _pending = pending;
    state = state.copyWith(
      submitting: true,
      preparations: {
        ...state.preparations,
        projectId: NewThreadPreparation(
          projectId: projectId,
          inputId: frozen.input.inputId,
          workspaceMode: frozen.project.workspaceMode,
        ),
      },
    );
    final binding = _client.attachments.newThreadBinding(projectId);
    final composer = binding.read();
    binding.write(
      SubmittingComposerThreadState(
        draft: composer.draft,
        attachments: composer.attachments,
        submissionRevision: composer.submissionRevision + 1,
        attachmentGeneration: composer.attachmentGeneration,
        inputId: frozen.input.inputId,
        cleanupFailureDraftIds: composer.cleanupFailureDraftIds,
      ),
    );
    unawaited(
      _submit(frozen)
          .then(completion.complete, onError: completion.completeError),
    );
    return pending;
  }

  Future<bool> _submit(FrozenStartSessionSubmission frozen) async {
    final binding = _client.attachments.newThreadBinding(frozen.projectId);
    StartNewThreadResult? acceptedResult;
    try {
      final result = await _client.threadCommands.submitNewThread(
        projectId: frozen.projectId,
        input: frozen.input,
        mode: frozen.project.mode,
        workspaceMode: frozen.project.workspaceMode.id,
        route: frozen.route,
        delegationMode: frozen.delegation.mode,
        delegationPreference: frozen.delegation.preference,
        onProgress: (progress) => _progress(frozen, progress),
      );
      if (result == null) {
        final failure = StateError('New Thread submission was not accepted');
        frozen.operation.reject(failure);
        await _client.attachments.completeFrozen(
          operationId: frozen.operation.id,
          accepted: false,
          clearCurrent: false,
          projectId: frozen.projectId,
          threadId: null,
        );
        _failure(binding.read(), frozen, failure);
        _preparationFailure(frozen, failure, known: true);
        return false;
      }
      acceptedResult = result;
      _clearPreparation(frozen);
      _observations.removeWhere((entry) => entry.isCancelled);
      _observations.add(
        observeSubmittedInput(
          client: _client,
          operation: frozen.operation,
          receipt: result.receipt,
        ),
      );
      final clear =
          !_closed &&
          state.revision == frozen.stamp.revision &&
          _client.attachments.newThreadStamp(frozen.projectId) ==
              frozen.attachmentStamp;
      if (!_closed) {
        final composer = binding.read();
        binding.write(
          ComposerThreadState.idle(
            draft: clear ? '' : composer.draft,
            attachments: clear ? const [] : composer.attachments,
            submissionRevision: composer.submissionRevision,
            attachmentGeneration: composer.attachmentGeneration,
            cleanupFailureDraftIds: composer.cleanupFailureDraftIds,
          ),
        );
        if (clear) {
          state = state.copyWith(
            projects: {...state.projects}..remove(frozen.projectId),
            revision: state.revision + 1,
          );
          _permits.remove(frozen.projectId)?.release();
        }
      }
      await _client.attachments.completeFrozen(
        operationId: frozen.operation.id,
        accepted: true,
        clearCurrent: clear,
        projectId: frozen.projectId,
        threadId: result.thread.id,
      );
      return true;
    } catch (cause) {
      final error = cause is NewThreadStartFailed ? cause.error : cause;
      // A transport error cannot replace this invocation's typed terminal outcome.
      final rejected = cause is NewThreadStartFailed;
      if (acceptedResult != null) {
        frozen.operation.syncFailed(error);
        await _client.attachments.completeFrozen(
          operationId: frozen.operation.id,
          accepted: true,
          clearCurrent: false,
          projectId: frozen.projectId,
          threadId: acceptedResult.thread.id,
        );
      } else if (rejected) {
        frozen.operation.reject(error);
        await _client.attachments.completeFrozen(
          operationId: frozen.operation.id,
          accepted: false,
          clearCurrent: false,
          projectId: frozen.projectId,
          threadId: null,
        );
      } else {
        _unknown[frozen.projectId] = (frozen.stamp, frozen.attachmentStamp);
        frozen.operation.unknownOutcome(error);
      }
      _failure(binding.read(), frozen, error);
      if (acceptedResult == null)
        _preparationFailure(frozen, error, known: rejected);
      return false;
    }
  }

  void _progress(
    FrozenStartSessionSubmission frozen,
    ThreadPreparationProgress progress,
  ) {
    if (_closed) return;
    final current = state.preparations[frozen.projectId];
    if (current == null ||
        current.inputId != frozen.input.inputId ||
        current.phase != NewThreadPreparationPhase.preparing)
      return;
    if (current.progress != null &&
        progress.stage.index < current.progress!.stage.index)
      return;
    state = state.copyWith(
      preparations: {
        ...state.preparations,
        frozen.projectId: current.withProgress(progress),
      },
    );
  }

  void _preparationFailure(
    FrozenStartSessionSubmission frozen,
    Object error, {
    required bool known,
  }) {
    if (_closed) return;
    final current = state.preparations[frozen.projectId];
    if (current == null || current.inputId != frozen.input.inputId) return;
    state = state.copyWith(
      preparations: {
        ...state.preparations,
        frozen.projectId: current.withFailure(error, known: known),
      },
    );
  }

  void _clearPreparation(FrozenStartSessionSubmission frozen) {
    if (_closed ||
        state.preparations[frozen.projectId]?.inputId != frozen.input.inputId)
      return;
    state = state.copyWith(
      preparations: {...state.preparations}..remove(frozen.projectId),
    );
  }

  void _failure(
    ComposerThreadState composer,
    FrozenStartSessionSubmission frozen,
    Object error,
  ) {
    if (_closed) return;
    if (state.revision != frozen.stamp.revision ||
        _client.attachments.newThreadStamp(frozen.projectId) !=
            frozen.attachmentStamp) {
      _client.attachments
          .newThreadBinding(frozen.projectId)
          .write(
            ComposerThreadState.idle(
              draft: composer.draft,
              attachments: composer.attachments,
              submissionRevision: composer.submissionRevision,
              attachmentGeneration: composer.attachmentGeneration,
              cleanupFailureDraftIds: composer.cleanupFailureDraftIds,
            ),
          );
      return;
    }
    _client.attachments
        .newThreadBinding(frozen.projectId)
        .write(
          ComposerThreadState.failure(
            error: error.toString(),
            draft: composer.draft,
            attachments: composer.attachments,
            submissionRevision: composer.submissionRevision,
            attachmentGeneration: composer.attachmentGeneration,
            cleanupFailureDraftIds: composer.cleanupFailureDraftIds,
            inputId: frozen.input.inputId,
          ),
        );
  }

  /// Freezes the current draft selection for submission or attachment admission.
  ModeModelRouteView resolveRoute(ThreadModeId mode) {
    final settings = _client.settings.state;
    if (!settings.configLoaded)
      throw StateError('Settings are not available yet');
    final canonical = ModelRouteQueries.modeRoute(
      settings.canonical?.modeModelRoutes ?? const [],
      mode,
    );
    final route = overlayStartSessionRoute(
      mode: mode,
      laneRoute: canonical,
      modelIntent: state.modelIntentFor(mode),
      effortIntent: state.effortIntentFor(mode),
    );
    if (route == null || route.accountId.isEmpty || route.modelId.isEmpty) {
      throw StateError('A complete model route is required');
    }
    final account = settings.canonical?.accounts
        .where((value) => value.id == route.accountId)
        .firstOrNull;
    final model = account?.models
        .where((value) => value.modelId == route.modelId)
        .firstOrNull;
    // Candidate lists use typeSupport; admission of an existing desired route
    // stays with Runtime. Only explicit unified disablement is resolved here.
    if (model == null || !model.enabled) {
      throw StateError('The selected model is unavailable');
    }
    return ModeModelRouteView(
      modeId: mode,
      accountId: route.accountId,
      modelId: route.modelId,
      effort: route.effort.isEmpty
          ? model.defaultReasoningEffort
          : route.effort,
    );
  }

  void _reserve(String projectId) => _permits.putIfAbsent(
    projectId,
    () => _client.budget.acquire(ResourceKind.draft, owner: 'start:$projectId'),
  );

  Future<void> discardProject(String projectId) async {
    if (_closed) return;
    state = state.copyWith(
      projects: {...state.projects}..remove(projectId),
      preparations: {...state.preparations}..remove(projectId),
      revision: state.revision + 1,
    );
    _permits.remove(projectId)?.release();
    await _client.attachments.discardProject(projectId);
  }

  Future<void> close() => _closing ??= _close();

  Future<void> _close() async {
    _closed = true;
    await _pending;
    for (final observation in _observations) {
      observation.cancel();
    }
    _observations.clear();
    for (final permit in _permits.values) {
      permit.release();
    }
    _permits.clear();
  }
}

final class FrozenStartSessionSubmission {
  const FrozenStartSessionSubmission({
    required this.stamp,
    required this.attachmentStamp,
    required this.operation,
    required this.projectId,
    required this.project,
    required this.route,
    required this.delegation,
    required this.input,
  });
  final DraftStamp stamp;
  final DraftStamp attachmentStamp;
  final OperationHandle operation;
  final String projectId;
  final StartSessionProjectDraft project;
  final ModeModelRouteView route;
  final DelegationSettingsView delegation;
  final StudioPromptInput input;
}
