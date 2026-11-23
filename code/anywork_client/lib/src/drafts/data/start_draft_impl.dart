import 'dart:async';

import '../../../acp_sessions.dart';
import '../../accounts/domain/account_identity.dart';
import '../../commands/mutation_board.dart';
import '../../contracts/stamps.dart';
import '../../observation/latest_value.dart';
import '../../observation/read_model.dart';
import '../../../models.dart';
import 'drafts_dependencies.dart';
import '../domain/draft_owners.dart';
import '../domain/draft_errors.dart';
import '../../studio/model_route_queries.dart';
import 'submission_observation.dart';
import 'composer_draft_impl.dart';

/// Project drafts and mode-specific route intent survive route observers.
final class StartSessionDraftImpl extends ReadModel<StartSessionDraft>
    implements StartSessionDraftOwner {
  StartSessionDraftImpl(this._dependencies) : super(const StartSessionDraft()) {
    var bindings = {
      for (final project
          in _dependencies.project.value.projects?.values ??
              const <StudioProject>[])
        project.id: (project.path, project.sshAlias),
    };
    _observations.add(
      _dependencies.project.watch((value) {
        if (_closed) return;
        final next = {
          for (final project
              in value.projects?.values ?? const <StudioProject>[])
            project.id: (project.path, project.sshAlias),
        };
        final changed = [
          for (final entry in state.projects.entries)
            if (entry.value.acpAccountId != null &&
                bindings[entry.key] != next[entry.key])
              entry.key,
        ];
        bindings = next;
        for (final workspaceId in changed) {
          _invalidateAcpBinding(workspaceId);
        }
      }),
    );
    final accounts = _dependencies.accountSummaries;
    if (accounts != null) {
      var connections = {
        for (final account in accounts.value.accounts)
          account.identity: (account.acpEnabled, account.acpConnectionRevision),
      };
      _observations.add(
        accounts.watch((value) {
          if (_closed) return;
          final next = {
            for (final account in value.accounts)
              account.identity: (
                account.acpEnabled,
                account.acpConnectionRevision,
              ),
          };
          final changed = [
            for (final entry in state.projects.entries)
              if (entry.value.acpAccountId case final accountId?)
                if (connections[AcpAccountIdentity(accountId)] !=
                    next[AcpAccountIdentity(accountId)])
                  entry.key,
          ];
          connections = next;
          for (final workspaceId in changed) {
            _invalidateAcpBinding(workspaceId);
          }
        }),
      );
    }
  }

  final DraftsDependencies _dependencies;
  final List<Observation> _observations = [];
  final Map<String, (DraftStamp, DraftStamp)> _unknown = {};
  final Set<String> _acpUnknown = {};
  final Map<String, int> _acpGenerations = {};
  final Map<String, Completer<void>> _acpReadyWaits = {};
  final Map<
    String,
    ({int generation, String accountId, AcpConversationSession owner})
  >
  _acpPrepared = {};
  final Map<String, ({int generation, Future<void> task})> _acpPreparing = {};
  final Map<String, Map<AcpConfigId, AcpSessionConfigValueView>>
  _acpConfigIntents = {};
  final Map<String, AcpModeId> _acpModeIntents = {};
  final Map<
    String,
    ({
      int generation,
      String workspacePath,
      String? sshAlias,
      ComposerDraftImpl composer,
    })
  >
  _acpCreatedByWorkspace = {};
  final LatestValue<Map<String, List<ComposerSubmission>>> _submissions =
      LatestValue<Map<String, List<ComposerSubmission>>>(
        const <String, List<ComposerSubmission>>{},
      );
  final Map<String, Map<String, ComposerSubmission>> _submissionByWorkspace =
      {};
  final Map<String, FrozenStartSessionSubmission> _frozenByInput = {};
  final Map<String, Future<bool>> _pendingByWorkspace = {};
  final Map<String, Future<bool>> _retryByInput = {};
  final Map<String, Future<void>> _removeTasks = {};
  final Map<String, Future<void>> _presentationTasks = {};
  final Set<String> _presentedInputIds = {};
  Future<void>? _closing;
  bool _closed = false;

  void _invalidateAcpBinding(String workspaceId) {
    _acpGenerations[workspaceId] = (_acpGenerations[workspaceId] ?? 0) + 1;
    _acpCreatedByWorkspace.remove(workspaceId);
    _publishAcpPreparation(
      workspaceId,
      AcpDraftPreparing(_acpGenerations[workspaceId]!),
    );
    unawaited(prepareAcp(workspaceId));
  }

  @override
  ValueObservation<Map<String, List<ComposerSubmission>>> get submissions =>
      _submissions;

  void _publishSubmissions() => _submissions.publish(
    Map.unmodifiable({
      for (final entry in _submissionByWorkspace.entries)
        if (entry.value.isNotEmpty)
          entry.key: List<ComposerSubmission>.unmodifiable(entry.value.values),
    }),
  );

  @override
  void markInputsPresented(Iterable<String> inputIds) {
    var changed = false;
    var preparationsChanged = false;
    final preparations = {...state.preparations};
    for (final inputId in inputIds) {
      if (!_presentedInputIds.add(inputId)) continue;
      for (final entry in _submissionByWorkspace.entries) {
        final submission = entry.value[inputId];
        changed = entry.value.remove(inputId) != null || changed;
        if (submission?.phase == ComposerSubmissionPhase.unknownOutcome) {
          for (final observation in _observations.where(
            (item) =>
                item is InputSubmissionObservation && item.inputId == inputId,
          )) {
            observation.cancel();
          }
        }
      }
      final frozen = _frozenByInput.remove(inputId);
      if (frozen != null) {
        if (_unknown[frozen.workspaceId] ==
            (frozen.stamp, frozen.attachmentStamp)) {
          _unknown.remove(frozen.workspaceId);
        }
        if (preparations[frozen.workspaceId]?.inputId == inputId) {
          preparations.remove(frozen.workspaceId);
          preparationsChanged = true;
        }
        _releasePresentedInput(inputId, frozen);
      }
    }
    if (preparationsChanged) {
      state = state.copyWith(preparations: preparations);
    }
    if (changed) _publishSubmissions();
  }

  void _releasePresentedInput(
    String inputId,
    FrozenStartSessionSubmission frozen,
  ) {
    final completion = Completer<void>();
    final task = completion.future;
    _presentationTasks[inputId] = task;
    unawaited(task.then<void>((_) {}, onError: (Object _, StackTrace __) {}));
    unawaited(
      _releaseFrozen(frozen)
          .then(completion.complete, onError: completion.completeError),
    );
  }

  Future<void> _releaseFrozen(FrozenStartSessionSubmission frozen) async {
    await _dependencies.attachments.completeFrozen(
      operationId: frozen.operation.id,
      accepted: false,
      clearCurrent: false,
      workspaceId: frozen.workspaceId,
      threadId: null,
    );
    final unresolved = _dependencies.attachments.unresolvedAttachmentIds
        .toSet();
    final failedIds = frozen.input.attachmentDraftIds
        .where(unresolved.contains)
        .toList();
    if (failedIds.isNotEmpty) throw AttachmentCleanupUnresolved(failedIds);
  }

  void updateDraft(String workspaceId, String text) {
    final project = state.forProject(workspaceId);
    if (project.text == text && state.projects.containsKey(workspaceId)) return;
    _editProject(workspaceId, project.copyWith(text: text));
  }

  void setMode(String workspaceId, ThreadModeId mode) {
    final project = state.forProject(workspaceId);
    if (project.mode == mode && state.projects.containsKey(workspaceId)) return;
    _editProject(workspaceId, project.copyWith(mode: mode));
  }

  void setAcpService(String workspaceId, String? accountId) {
    if (_pendingByWorkspace.containsKey(workspaceId)) return;
    if (accountId != null && accountId.trim().isEmpty) {
      throw ArgumentError.value(accountId, 'accountId');
    }
    final project = state.forProject(workspaceId);
    if (project.acpAccountId == accountId) return;
    _editProject(workspaceId, project.copyWith(acpAccountId: accountId));
  }

  void setWorkspaceMode(String workspaceId, ThreadWorkspaceMode mode) {
    final workspace = _dependencies.project.value.projects?.values
        .where((project) => project.id == workspaceId)
        .firstOrNull;
    if (workspace?.isStandalone == true && mode.isWorktree) return;
    final project = state.forProject(workspaceId);
    if (project.workspaceMode == mode &&
        state.projects.containsKey(workspaceId))
      return;
    _editProject(workspaceId, project.copyWith(workspaceMode: mode));
  }

  void setDelegationModeOverride(String workspaceId, DelegationMode? mode) {
    final project = state.forProject(workspaceId);
    if (project.delegationModeOverride == mode) return;
    _editProject(workspaceId, project.copyWith(delegationModeOverride: mode));
  }

  void setDelegationPreferenceOverride(
    String workspaceId,
    DelegationPreference? preference,
  ) {
    final project = state.forProject(workspaceId);
    if (project.delegationPreferenceOverride == preference) return;
    _editProject(
      workspaceId,
      project.copyWith(delegationPreferenceOverride: preference),
    );
  }

  void _editProject(String workspaceId, StartSessionProjectDraft project) {
    if (_closed) return;
    final previous = state.forProject(workspaceId);
    final bindingChanged =
        previous.acpAccountId != project.acpAccountId ||
        previous.workspaceMode != project.workspaceMode ||
        previous.delegationModeOverride != project.delegationModeOverride ||
        previous.delegationPreferenceOverride !=
            project.delegationPreferenceOverride;
    if (bindingChanged) {
      _acpGenerations[workspaceId] = (_acpGenerations[workspaceId] ?? 0) + 1;
      _acpCreatedByWorkspace.remove(workspaceId);
    }
    state = state.copyWith(
      projects: {...state.projects, workspaceId: project},
      acpPreparations: bindingChanged
          ? ({...state.acpPreparations}
              ..remove(workspaceId)
              ..addAll(
                project.acpAccountId == null
                    ? {}
                    : {
                        workspaceId: AcpDraftPreparing(
                          _acpGenerations[workspaceId]!,
                        ),
                      },
              ))
          : state.acpPreparations,
      revision: state.revision + 1,
    );
    if (bindingChanged) unawaited(prepareAcp(workspaceId));
  }

  @override
  Future<void> prepareAcp(String workspaceId, {bool retry = false}) {
    if (_closed ||
        _dependencies.isClosed ||
        _acpCreatedByWorkspace.containsKey(workspaceId)) {
      return Future.value();
    }
    final generation = _acpGenerations[workspaceId] ?? 0;
    final pending = _acpPreparing[workspaceId];
    if (pending?.generation == generation) return pending!.task;
    final preparation = state.acpPreparations[workspaceId];
    if (!retry &&
        preparation?.generation == generation &&
        (preparation is AcpDraftReady ||
            preparation is AcpDraftFailed ||
            preparation is AcpDraftNeedsConfiguration))
      return Future.value();
    final completion = Completer<void>();
    final task = completion.future;
    _acpPreparing[workspaceId] = (generation: generation, task: task);
    unawaited(() async {
      try {
        await pending?.task;
        await _prepareAcp(workspaceId, generation);
      } finally {
        if (identical(_acpPreparing[workspaceId]?.task, task))
          _acpPreparing.remove(workspaceId);
        completion.complete();
      }
    }());
    return task;
  }

  void _publishAcpPreparation(String workspaceId, AcpDraftPreparation? value) {
    state = state.copyWith(
      acpPreparations: {
        ...state.acpPreparations,
        if (value != null) workspaceId: value,
      }..removeWhere((key, _) => key == workspaceId && value == null),
    );
  }

  Future<void> _prepareAcp(String workspaceId, int generation) async {
    bool current() =>
        !_closed &&
        !_dependencies.isClosed &&
        (_acpGenerations[workspaceId] ?? 0) == generation;
    if (!current()) return;
    final sessions = _dependencies.acpSessions;
    if (sessions == null) {
      if (state.forProject(workspaceId).acpAccountId != null) {
        _publishAcpPreparation(
          workspaceId,
          AcpDraftFailed(
            generation,
            StateError('The ACP business port is not available'),
          ),
        );
      }
      return;
    }
    var dispatched = false;
    var admitted = false;
    try {
      if (_acpUnknown.contains(workspaceId)) {
        throw StateError('The previous ACP preparation outcome is unresolved');
      }
      final previous = _acpPrepared[workspaceId];
      if (previous != null) {
        final result = await sessions.discardDraft(previous.owner);
        if (!result.localComplete)
          throw StateError('Previous ACP draft cleanup is incomplete');
        if (previous.accountId == state.forProject(workspaceId).acpAccountId) {
          _acpConfigIntents[workspaceId] = {
            ...?_acpConfigIntents[workspaceId],
            ...previous.owner.configIntents,
          };
          if (previous.owner.modeIntent case final mode?) {
            _acpModeIntents[workspaceId] = mode;
          }
        } else {
          _acpConfigIntents.remove(workspaceId);
          _acpModeIntents.remove(workspaceId);
        }
        _acpPrepared.remove(workspaceId);
      }
      if (!current()) return;
      final draft = state.forProject(workspaceId);
      if (draft.acpAccountId == null) {
        _publishAcpPreparation(workspaceId, null);
        return;
      }
      _publishAcpPreparation(workspaceId, AcpDraftPreparing(generation));
      final account = _dependencies.accountSummaries?.value.account(
        AcpAccountIdentity(draft.acpAccountId!),
      );
      if (account?.acpEnabled != true ||
          account?.acpConnectionRevision == null) {
        throw StateError('The ACP service is not available');
      }
      dispatched = true;
      final owner = await sessions.openConversation(
        OpenAcpSessionRequestView(
          accountId: draft.acpAccountId!,
          expectedConnectionRevision: BigInt.from(
            account!.acpConnectionRevision!,
          ),
          workspaceId: workspaceId,
          intent: AcpDraftIntentView(
            workspaceMode: draft.workspaceMode,
            delegationMode: draft.delegationModeOverride,
            delegationPreference: draft.delegationPreferenceOverride,
          ),
        ),
      );
      admitted = true;
      _acpPrepared[workspaceId] = (
        generation: generation,
        accountId: draft.acpAccountId!,
        owner: owner,
      );
      if (!current()) {
        final result = await sessions.discardDraft(owner);
        if (!result.localComplete)
          throw StateError('Retired ACP draft cleanup is incomplete');
        _acpPrepared.remove(workspaceId);
        return;
      }
      await _waitForAcpReady(workspaceId, owner, isCurrent: current);
      if (_acpModeIntents[workspaceId] case final mode?) {
        if (owner.state.configOptions != null ||
            owner.state.modes?.availableModes.any(
                  (value) => value.id == mode,
                ) !=
                true) {
          throw StateError(
            'A previously selected ACP mode is unavailable: ${mode.value}',
          );
        }
        await _confirmAcpConfiguration(
          workspaceId,
          owner,
          owner.setMode(mode),
          current,
        );
      }
      for (final entry
          in (_acpConfigIntents[workspaceId] ??
                  const <AcpConfigId, AcpSessionConfigValueView>{})
              .entries) {
        if (!current()) return;
        final option = owner.state.configOptions
            ?.where((value) => value.id == entry.key)
            .firstOrNull;
        final value = entry.value;
        final supported = switch ((option?.kind, value)) {
          (AcpBooleanConfigView(), AcpBooleanConfigValueView()) => true,
          (
            AcpSelectConfigView(options: final choices),
            AcpSelectConfigValueView(:final value),
          ) =>
            switch (choices) {
              AcpUngroupedOptionsView(:final options) => options.any(
                (option) => option.value == value,
              ),
              AcpGroupedOptionsView(:final groups) => groups.any(
                (group) => group.options.any((option) => option.value == value),
              ),
            },
          _ => false,
        };
        if (!supported) {
          _publishAcpPreparation(
            workspaceId,
            AcpDraftNeedsConfiguration(
              generation,
              owner.state.target!.threadId,
              StateError(
                'A previously selected ACP option is unavailable: ${entry.key.value}',
              ),
            ),
          );
          return;
        }
        await _confirmAcpConfiguration(
          workspaceId,
          owner,
          owner.configure(entry.key, value),
          current,
        );
      }
      if (current())
        _publishAcpPreparation(
          workspaceId,
          AcpDraftReady(generation, owner.state.target!.threadId),
        );
    } catch (error) {
      if (dispatched && !admitted && error is! AcpBusinessFailureView)
        _acpUnknown.add(workspaceId);
      if (current()) {
        final prepared = _acpPrepared[workspaceId];
        _publishAcpPreparation(
          workspaceId,
          prepared?.owner.state.ready == true
              ? AcpDraftNeedsConfiguration(
                  generation,
                  prepared!.owner.state.target!.threadId,
                  error,
                )
              : AcpDraftFailed(generation, error),
        );
      }
    }
  }

  Future<void> _confirmAcpConfiguration(
    String workspaceId,
    AcpConversationSession owner,
    Future<void> command,
    bool Function() isCurrent,
  ) async {
    // The original protocol owner settles an in-flight command when retired.
    // A directory change wakes this waiter so the queued replacement can close it.
    unawaited(
      command.then<void>((_) {}, onError: (Object _, StackTrace __) {}),
    );
    await _waitForAcpReady(
      workspaceId,
      owner,
      isCurrent: isCurrent,
      waitForConfiguration: true,
    );
    await command;
  }

  @override
  void acceptAcpConfiguration(String workspaceId) {
    final preparation = state.acpPreparations[workspaceId];
    final prepared = _acpPrepared[workspaceId];
    if (preparation is! AcpDraftNeedsConfiguration ||
        prepared == null ||
        prepared.generation != (_acpGenerations[workspaceId] ?? 0))
      return;
    if (prepared.owner.state.configPending) return;
    prepared.owner.dismissError();
    _acpConfigIntents.remove(workspaceId);
    _acpModeIntents.remove(workspaceId);
    _publishAcpPreparation(
      workspaceId,
      AcpDraftReady(preparation.generation, preparation.threadId),
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
    final snapshot = _dependencies.settings.value.canonical;
    final canonical = ModelRouteQueries.modeRoute(
      snapshot?.modeModelRoutes ?? const [],
      mode,
    );
    final changed = previous != null
        ? previous != next
        : canonical?.accountId != accountId || canonical?.modelId != modelId;
    final efforts = {...state.effortIntents};
    final serviceTiers = {...state.serviceTierIntents};
    if (changed) {
      serviceTiers.remove(mode.id);
      final effort = ModelRouteQueries.effortAfterModelSelection(
        ModelRouteQueries.model(
          _dependencies.modelAccounts(),
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
      serviceTierIntents: serviceTiers,
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

  @override
  void setServiceTierIntent(ThreadModeId mode, String? serviceTier) {
    if (_closed || state.serviceTierIntents[mode.id] == serviceTier) return;
    final route = resolveRoute(mode);
    final intents = {...state.serviceTierIntents};
    if (serviceTier == null) {
      intents.remove(mode.id);
    } else {
      intents[mode.id] = serviceTier;
    }
    state = state.copyWith(
      modelIntents: {
        ...state.modelIntents,
        mode.id: StartSessionModelIntent(
          accountId: route.accountId,
          modelId: route.modelId,
        ),
      },
      serviceTierIntents: intents,
      revision: state.revision + 1,
    );
  }

  /// Synchronous freeze: no queued settings write or later cache read may
  /// change the project, mode, route, text or attachment IDs sent by this call.
  FrozenStartSessionSubmission _freezeForSubmit(String workspaceId) {
    if (_closed || _dependencies.isClosed)
      throw StateError('The start draft is closed');
    final selection = _dependencies.selection.value;
    if (selection.selectedProjectId != workspaceId ||
        selection.selectedThreadId != null) {
      throw StateError('New Thread submission target is no longer available');
    }
    final projects =
        _dependencies.project.value.projects?.values ?? const <StudioProject>[];
    final workspace = projects
        .where((project) => project.id == workspaceId)
        .firstOrNull;
    if (workspace == null) {
      throw StateError('Project is no longer available');
    }
    final recoveryIssue = recoveryIssueBlockingExecution(
      _dependencies.recovery.value.value?.values ?? const [],
      workspaceId: workspaceId,
    );
    if (recoveryIssue != null) throw recoveryIssue.blockedFailure();
    final project = state.forProject(workspaceId);
    if (workspace.isStandalone && project.workspaceMode.isWorktree) {
      throw StateError('Standalone workspaces only support local mode');
    }
    final composer = _dependencies.attachments.state.newThread(workspaceId);
    if (project.text.trim().isEmpty && composer.attachments.isEmpty) {
      throw StateError('Cannot submit an empty draft');
    }
    final stamp = DraftStamp(
      draftId: 'start:$workspaceId',
      revision: state.revision,
    );
    final attachmentStamp = _dependencies.attachments.newThreadStamp(
      workspaceId,
    );
    if (_unknown[workspaceId] == (stamp, attachmentStamp)) {
      throw StateError('The previous submission outcome is unknown');
    }
    final route = resolveRoute(project.mode);
    final serviceTier = state.serviceTierIntents[project.mode.id];
    final defaults = _dependencies.settings.value.canonical!.delegation;
    final delegation = project.resolveDelegation(defaults);
    final operation = _dependencies.mutations.begin(
      target: 'start:$workspaceId',
      draft: stamp,
    );
    final input = StudioPromptInput(
      inputId: operation.id.value,
      text: project.text,
      attachmentDraftIds: List.unmodifiable(
        composer.attachments.map((item) => item.id),
      ),
    );
    final attachmentViews = ComposerSubmission.freezeAttachments(
      composer.attachments,
    );
    try {
      _dependencies.attachments.retainFrozen(
        operationId: operation.id,
        binding: _dependencies.attachments.newThreadBinding(workspaceId),
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
      workspaceId: workspaceId,
      project: project,
      route: route,
      serviceTier: serviceTier,
      delegation: delegation,
      input: input,
      attachments: attachmentViews,
    );
  }

  Future<bool> submit(String workspaceId) {
    if (_closed || _dependencies.isClosed) return Future<bool>.value(false);
    final existing = _pendingByWorkspace[workspaceId];
    if (existing != null) return Future<bool>.value(false);
    final completion = Completer<bool>();
    late final Future<bool> pending;
    pending = completion.future.whenComplete(() {
      if (identical(_pendingByWorkspace[workspaceId], pending)) {
        final removed = _pendingByWorkspace.remove(workspaceId);
        if (removed == null) return;
        if (!_closed) {
          state = state.copyWith(submitting: _pendingByWorkspace.isNotEmpty);
        }
      }
    });
    // Publish ownership before notifying synchronous observers or starting transport work.
    _pendingByWorkspace[workspaceId] = pending;
    unawaited(
      _prepareAndSubmit(workspaceId)
          .then(completion.complete, onError: completion.completeError),
    );
    return pending;
  }

  Future<bool> _prepareAndSubmit(String workspaceId) async {
    if (state.forProject(workspaceId).acpAccountId != null) {
      return _createAcpSession(workspaceId);
    }
    FrozenStartSessionSubmission? frozen;
    InputSubmissionObservation? evidence;
    try {
      frozen = _freezeForSubmit(workspaceId);
      evidence = registerSubmittedInput(
        dependencies: _dependencies,
        operation: frozen.operation,
        inputId: frozen.input.inputId,
      );
      _observations.removeWhere((entry) => entry.isCancelled);
      _observations.add(evidence);
      _frozenByInput[frozen.input.inputId] = frozen;
      if (_presentedInputIds.contains(frozen.input.inputId)) {
        _frozenByInput.remove(frozen.input.inputId);
        _releasePresentedInput(frozen.input.inputId, frozen);
      } else {
        _submissionByWorkspace.putIfAbsent(
          workspaceId,
          () => <String, ComposerSubmission>{},
        )[frozen.input.inputId] = ComposerSubmission(
          inputId: frozen.input.inputId,
          text: frozen.input.text,
          attachments: frozen.attachments,
          phase: ComposerSubmissionPhase.sending,
        );
      }
    } catch (error) {
      evidence?.cancel();
      if (frozen != null) {
        frozen.operation.reject(error);
        await _dependencies.attachments.completeFrozen(
          operationId: frozen.operation.id,
          accepted: false,
          clearCurrent: false,
          workspaceId: workspaceId,
          threadId: null,
        );
      }
      if (!_closed)
        _dependencies.attachments.reportNewThreadFailure(workspaceId, error);
      return false;
    }
    final binding = _dependencies.attachments.newThreadBinding(workspaceId);
    final composer = binding.read();
    _dependencies.attachments.detachFrozenDraft(frozen.operation.id);
    binding.write(
      ComposerThreadState.idle(
        draft: '',
        attachments: const [],
        submissionRevision: composer.submissionRevision + 1,
        attachmentGeneration: composer.attachmentGeneration,
        cleanupFailureDraftIds: composer.cleanupFailureDraftIds,
      ),
    );
    if (state.revision == frozen.stamp.revision) {
      final currentProject = state.forProject(workspaceId);
      state = state.copyWith(
        projects: {
          ...state.projects,
          workspaceId: currentProject.copyWith(text: ''),
        },
        revision: state.revision + 1,
      );
    }
    state = state.copyWith(
      submitting: true,
      preparations: {
        ...state.preparations,
        workspaceId: NewThreadPreparation(
          workspaceId: workspaceId,
          inputId: frozen.input.inputId,
          workspaceMode: frozen.project.workspaceMode,
        ),
      },
    );
    _publishSubmissions();
    return _submit(frozen, evidence);
  }

  Future<bool> _createAcpSession(String workspaceId) async {
    var dispatched = false;
    var created = false;
    ({int generation, String accountId, AcpConversationSession owner})?
    committing;
    OperationId? frozenId;
    String? createdThreadId;
    try {
      if (_closed || _dependencies.isClosed) {
        throw StateError('The start draft is closed');
      }
      if (_acpUnknown.contains(workspaceId)) {
        throw StateError('The previous ACP creation outcome is unresolved');
      }
      final selection = _dependencies.selection.value;
      final navigation = _dependencies.selectionNavigationGeneration?.call();
      final generation = _acpGenerations[workspaceId] ?? 0;
      final workspace = _dependencies.project.value.projects?.values
          .where((value) => value.id == workspaceId)
          .firstOrNull;
      if (workspace == null || workspace.path.isEmpty) {
        throw StateError('Project is no longer available');
      }
      bool current() =>
          !_closed &&
          !_dependencies.isClosed &&
          (_acpGenerations[workspaceId] ?? 0) == generation &&
          (_dependencies.project.value.projects?.values.any(
                (value) =>
                    value.id == workspaceId &&
                    value.path == workspace.path &&
                    value.sshAlias == workspace.sshAlias,
              ) ??
              false);
      bool originalDraft() =>
          current() &&
          navigation == _dependencies.selectionNavigationGeneration?.call();
      final previous = _acpCreatedByWorkspace[workspaceId];
      if (selection.selectedProjectId != workspaceId ||
          (selection.selectedThreadId != null &&
              selection.selectedThreadId != previous?.composer.threadId)) {
        throw StateError('New Thread submission target is no longer available');
      }
      if (previous != null &&
          previous.generation == generation &&
          previous.workspacePath == workspace.path &&
          previous.sshAlias == workspace.sshAlias) {
        state = state.copyWith(submitting: true);
        if (!current()) return false;
        final sent = await previous.composer.submitInitialAcp();
        if (sent) {
          await _transferAcpFollowup(
            workspaceId,
            previous.composer,
            originalDraft,
          );
        }
        var followupNavigation = navigation;
        if (originalDraft() &&
            identical(selection, _dependencies.selection.value)) {
          _dependencies.selectCreatedThread?.call(
            workspaceId,
            previous.composer.threadId,
          );
          followupNavigation = _dependencies.selectionNavigationGeneration
              ?.call();
        }
        if (!sent && current()) {
          _observeAcpFollowup(
            workspaceId,
            previous.composer,
            () =>
                current() &&
                followupNavigation ==
                    _dependencies.selectionNavigationGeneration?.call(),
          );
        }
        if (sent) _acpCreatedByWorkspace.remove(workspaceId);
        return sent;
      }
      if (selection.selectedProjectId != workspaceId ||
          selection.selectedThreadId != null) {
        throw StateError('New Thread submission target is no longer available');
      }
      final project = state.forProject(workspaceId);
      final attachments = List<AttachmentDraftView>.unmodifiable(
        _dependencies.attachments.state.newThread(workspaceId).attachments,
      );
      if (project.text.trim().isEmpty && attachments.isEmpty) {
        throw StateError('Cannot submit an empty draft');
      }
      final recoveryIssue = recoveryIssueBlockingExecution(
        _dependencies.recovery.value.value?.values ?? const [],
        workspaceId: workspaceId,
      );
      if (recoveryIssue != null) throw recoveryIssue.blockedFailure();
      final sessions = _dependencies.acpSessions;
      final select = _dependencies.selectCreatedThread;
      final accounts = _dependencies.accountSummaries?.value;
      final account = accounts?.account(
        AcpAccountIdentity(project.acpAccountId!),
      );
      final revision = account?.acpConnectionRevision;
      if (sessions == null ||
          select == null ||
          accounts?.loaded != true ||
          account?.acpEnabled != true ||
          revision == null) {
        throw StateError('The ACP service is not available');
      }
      frozenId = OperationId(newPromptInputId());
      _dependencies.attachments.retainFrozen(
        operationId: frozenId,
        binding: _dependencies.attachments.newThreadBinding(workspaceId),
        attachmentIds: attachments.map((item) => item.id),
      );
      state = state.copyWith(submitting: true);
      if (!current()) {
        throw StateError('ACP creation cancelled before backend dispatch');
      }
      await prepareAcp(workspaceId);
      final prepared = _acpPrepared[workspaceId];
      final preparation = state.acpPreparations[workspaceId];
      if (preparation is AcpDraftFailed) throw preparation.error;
      if (preparation is AcpDraftNeedsConfiguration) throw preparation.error;
      if (prepared == null || prepared.generation != generation || !current()) {
        throw StateError('ACP draft is no longer available');
      }
      final owner = prepared.owner;
      await _waitForAcpReady(
        workspaceId,
        owner,
        isCurrent: current,
        waitForConfiguration: true,
      );
      // Transfer the original draft out before publication can be admitted.
      // A concurrent binding change may prepare a replacement, but cannot close
      // a session whose first submission is already being committed.
      committing = prepared;
      _acpPrepared.remove(workspaceId);
      _acpConfigIntents[workspaceId] = owner.configIntents;
      if (owner.modeIntent case final mode?)
        _acpModeIntents[workspaceId] = mode;
      _publishAcpPreparation(workspaceId, null);
      dispatched = true;
      await sessions.commitDraft(
        owner.state.target!,
        firstPromptText: project.text,
      );
      created = true;
      committing = null;
      final target = owner.state.target!;
      createdThreadId = target.threadId;
      final composer =
          _dependencies.composer(target.threadId) as ComposerDraftImpl;
      if (current()) {
        _acpCreatedByWorkspace[workspaceId] = (
          generation: generation,
          workspacePath: workspace.path,
          sshAlias: workspace.sshAlias,
          composer: composer,
        );
        _acpConfigIntents.remove(workspaceId);
        _acpModeIntents.remove(workspaceId);
      }
      await _dependencies.attachments.transferNewThread(
        workspaceId: workspaceId,
        threadId: target.threadId,
        destination: composer.binding,
        text: () => project.text,
        // A retired start draft cannot cancel the accepted business session.
        isCurrent: () => !_closed && !_dependencies.isClosed,
        frozenAttachments: attachments,
      );
      if (_closed || _dependencies.isClosed) return false;
      if (originalDraft() &&
          identical(state.forProject(workspaceId), project)) {
        state = state.copyWith(
          projects: {
            ...state.projects,
            workspaceId: project.copyWith(text: ''),
          },
          revision: state.revision + 1,
        );
      }
      final sent = await composer.submitInitialAcp();
      if (sent) {
        await _transferAcpFollowup(workspaceId, composer, originalDraft);
      }
      var followupNavigation = navigation;
      if (current() &&
          identical(selection, _dependencies.selection.value) &&
          navigation == _dependencies.selectionNavigationGeneration?.call()) {
        select(workspaceId, target.threadId);
        followupNavigation = _dependencies.selectionNavigationGeneration
            ?.call();
      }
      if (!sent && current()) {
        _observeAcpFollowup(
          workspaceId,
          composer,
          () =>
              current() &&
              followupNavigation ==
                  _dependencies.selectionNavigationGeneration?.call(),
        );
      }
      if (sent) _acpCreatedByWorkspace.remove(workspaceId);
      return sent;
    } catch (error) {
      if (!created && committing != null && error is AcpBusinessFailureView) {
        if (!_closed &&
            (_acpGenerations[workspaceId] ?? 0) == committing.generation) {
          _acpPrepared[workspaceId] = committing;
          _publishAcpPreparation(
            workspaceId,
            AcpDraftReady(
              committing.generation,
              committing.owner.state.target!.threadId,
            ),
          );
        } else {
          await _dependencies.acpSessions!.discardDraft(committing.owner);
        }
      }
      if (!created && dispatched && error is! AcpBusinessFailureView) {
        _acpUnknown.add(workspaceId);
      }
      if (!_closed) {
        _dependencies.attachments.reportNewThreadFailure(workspaceId, error);
      }
      return false;
    } finally {
      if (frozenId != null) {
        await _dependencies.attachments.completeFrozen(
          operationId: frozenId,
          accepted: false,
          clearCurrent: false,
          workspaceId: workspaceId,
          threadId: createdThreadId,
        );
      }
    }
  }

  void _observeAcpFollowup(
    String workspaceId,
    ComposerDraftImpl composer,
    bool Function() isCurrent,
  ) {
    late final Observation observation;
    observation = composer.source.watch((value) {
      if (!isCurrent()) {
        observation.cancel();
        return;
      }
      if (value is! IdleComposerThreadState ||
          value.draft.isNotEmpty ||
          value.attachments.isNotEmpty)
        return;
      observation.cancel();
      unawaited(
        _transferAcpFollowup(
          workspaceId,
          composer,
          isCurrent,
        ).catchError((Object error) => composer.reportFailure(error)),
      );
    });
    _observations.removeWhere((item) => item.isCancelled);
    _observations.add(observation);
  }

  Future<void> _transferAcpFollowup(
    String workspaceId,
    ComposerDraftImpl composer,
    bool Function() isCurrent,
  ) async {
    if (!isCurrent()) return;
    // Edits made in the created conversation take precedence over a late handoff.
    if (composer.state.draft.isNotEmpty ||
        composer.state.attachments.isNotEmpty) {
      return;
    }
    StartSessionProjectDraft? transferred;
    await _dependencies.attachments.transferNewThread(
      workspaceId: workspaceId,
      threadId: composer.threadId,
      destination: composer.binding,
      text: () {
        transferred = state.forProject(workspaceId);
        return transferred!.text;
      },
      isCurrent: () =>
          isCurrent() &&
          composer.state.draft.isEmpty &&
          composer.state.attachments.isEmpty,
    );
    if (isCurrent() && identical(state.forProject(workspaceId), transferred)) {
      state = state.copyWith(
        projects: {...state.projects}..remove(workspaceId),
        revision: state.revision + 1,
      );
    }
  }

  Future<void> _waitForAcpReady(
    String workspaceId,
    AcpConversationSession owner, {
    bool Function()? isCurrent,
    bool waitForConfiguration = false,
  }) async {
    final completion = Completer<void>();
    _acpReadyWaits[workspaceId] = completion;
    void check(AcpConversationState value) {
      if (completion.isCompleted) return;
      if (_closed ||
          isCurrent?.call() == false ||
          value.observationEnded ||
          value.disconnected ||
          value.error != null) {
        completion.completeError(
          value.error ??
              StateError('ACP creation ended before the session was ready'),
        );
      } else if (value.ready &&
          !value.openPending &&
          (!waitForConfiguration || !value.configPending)) {
        completion.complete();
      }
    }

    final observation = owner.source.watch(check);
    final draftObservation = source.watch((_) => check(owner.state));
    check(owner.state);
    try {
      await completion.future;
    } finally {
      observation.cancel();
      draftObservation.cancel();
      if (identical(_acpReadyWaits[workspaceId], completion)) {
        _acpReadyWaits.remove(workspaceId);
      }
    }
  }

  Future<bool> _submit(
    FrozenStartSessionSubmission frozen,
    InputSubmissionObservation evidence,
  ) async {
    if (_closed || _dependencies.isClosed) {
      final error = StateError('Submission cancelled before backend dispatch');
      evidence.cancel();
      frozen.operation.reject(error);
      await _dependencies.attachments.completeFrozen(
        operationId: frozen.operation.id,
        accepted: false,
        clearCurrent: false,
        workspaceId: frozen.workspaceId,
        threadId: null,
        retainForRetry: true,
      );
      _updateSubmission(
        frozen.workspaceId,
        frozen.input.inputId,
        ComposerSubmissionPhase.failed,
        error,
      );
      return false;
    }
    final binding = _dependencies.attachments.newThreadBinding(
      frozen.workspaceId,
    );
    StartNewThreadResult? acceptedResult;
    try {
      final result = await _dependencies.threadCommands.submitNewThread(
        workspaceId: frozen.workspaceId,
        input: frozen.input,
        mode: frozen.project.mode,
        workspaceMode: frozen.project.workspaceMode.id,
        route: frozen.route,
        serviceTier: frozen.serviceTier,
        delegationMode: frozen.delegation.mode,
        delegationPreference: frozen.delegation.preference,
        onProgress: (progress) => _progress(frozen, progress),
      );
      if (result == null) {
        final failure = StateError('New Thread submission was not accepted');
        evidence.cancel();
        frozen.operation.reject(failure);
        await _dependencies.attachments.completeFrozen(
          operationId: frozen.operation.id,
          accepted: false,
          clearCurrent: false,
          workspaceId: frozen.workspaceId,
          threadId: null,
          retainForRetry: true,
        );
        _failure(binding.read(), frozen, failure);
        _preparationFailure(frozen, failure, known: true);
        _updateSubmission(
          frozen.workspaceId,
          frozen.input.inputId,
          ComposerSubmissionPhase.failed,
          failure,
        );
        return false;
      }
      acceptedResult = result;
      if (result.thread.id != result.receipt.threadId)
        throw StateError('New Thread receipt identity mismatch');
      evidence.accept(result.receipt);
      _clearPreparation(frozen);
      final clear =
          !_closed &&
          state.revision == frozen.stamp.revision &&
          _dependencies.attachments.newThreadStamp(frozen.workspaceId) ==
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
          final currentProject = state.forProject(frozen.workspaceId);
          state = state.copyWith(
            projects: {
              ...state.projects,
              frozen.workspaceId: currentProject.copyWith(text: ''),
            },
            revision: state.revision + 1,
          );
        }
      }
      await _dependencies.attachments.completeFrozen(
        operationId: frozen.operation.id,
        accepted: true,
        clearCurrent: clear,
        workspaceId: frozen.workspaceId,
        threadId: result.thread.id,
      );
      _frozenByInput.remove(frozen.input.inputId);
      _submissionByWorkspace[frozen.workspaceId]?.remove(frozen.input.inputId);
      _publishSubmissions();
      return true;
    } catch (cause) {
      final error = switch (cause) {
        NewThreadStartFailed(:final error) => error,
        SubmissionNotSent(:final error) => error,
        _ => cause,
      };
      // A transport error cannot replace this invocation's typed terminal outcome.
      // Only the stream's typed failure or a deterministic pre-dispatch
      // rejection is a definite creation rejection; an interrupted stream is
      // still unknown even if its error has a known code.
      final rejected =
          cause is NewThreadStartFailed || cause is SubmissionNotSent;
      if (acceptedResult != null) {
        evidence.cancel();
        frozen.operation.syncFailed(error);
        await _dependencies.attachments.completeFrozen(
          operationId: frozen.operation.id,
          accepted: true,
          clearCurrent: false,
          workspaceId: frozen.workspaceId,
          threadId: acceptedResult.thread.id,
        );
      } else if (rejected) {
        evidence.cancel();
        frozen.operation.reject(error);
        await _dependencies.attachments.completeFrozen(
          operationId: frozen.operation.id,
          accepted: false,
          clearCurrent: false,
          workspaceId: frozen.workspaceId,
          threadId: null,
          retainForRetry: true,
        );
        _updateSubmission(
          frozen.workspaceId,
          frozen.input.inputId,
          ComposerSubmissionPhase.failed,
          error,
        );
      } else {
        if (!_presentedInputIds.contains(frozen.input.inputId)) {
          _unknown[frozen.workspaceId] = (frozen.stamp, frozen.attachmentStamp);
        } else {
          evidence.cancel();
        }
        frozen.operation.unknownOutcome(error);
        _updateSubmission(
          frozen.workspaceId,
          frozen.input.inputId,
          ComposerSubmissionPhase.unknownOutcome,
          error,
        );
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
    final current = state.preparations[frozen.workspaceId];
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
        frozen.workspaceId: current.withProgress(progress),
      },
    );
  }

  void _updateSubmission(
    String workspaceId,
    String inputId,
    ComposerSubmissionPhase phase, [
    Object? error,
  ]) {
    final existing = _submissionByWorkspace[workspaceId]?[inputId];
    if (existing == null) return;
    _submissionByWorkspace[workspaceId]![inputId] = existing.withPhase(
      phase,
      error: error,
    );
    _publishSubmissions();
  }

  @override
  Future<bool> retrySubmission(String workspaceId, String inputId) {
    final running = _retryByInput[inputId];
    if (running != null) return running;
    final submission = _submissionByWorkspace[workspaceId]?[inputId];
    final frozen = _frozenByInput[inputId];
    if (submission == null ||
        submission.phase != ComposerSubmissionPhase.failed ||
        frozen == null) {
      return Future<bool>.error(
        StateError('Submission is missing or is not retryable'),
      );
    }
    if (_closed || _dependencies.isClosed) {
      return Future<bool>.error(StateError('The start draft is closed'));
    }
    if (_pendingByWorkspace[workspaceId] != null) {
      return Future<bool>.error(
        StateError('A Thread creation is already in progress for this project'),
      );
    }
    final completion = Completer<bool>();
    late final Future<bool> retry;
    retry = completion.future.whenComplete(() {
      if (identical(_retryByInput[inputId], retry)) {
        final removed = _retryByInput.remove(inputId);
        if (removed == null) return;
      }
      if (identical(_pendingByWorkspace[workspaceId], retry)) {
        final removed = _pendingByWorkspace.remove(workspaceId);
        if (removed == null) return;
        if (!_closed) {
          state = state.copyWith(submitting: _pendingByWorkspace.isNotEmpty);
        }
      }
    });
    _retryByInput[inputId] = retry;
    _pendingByWorkspace[workspaceId] = retry;
    if (!_closed) state = state.copyWith(submitting: true);
    unawaited(
      _retryFrozen(
        workspaceId,
        inputId,
        frozen,
      ).then(completion.complete, onError: completion.completeError),
    );
    return retry;
  }

  Future<bool> _retryFrozen(
    String workspaceId,
    String previousInputId,
    FrozenStartSessionSubmission previous,
  ) async {
    final operation = _dependencies.mutations.begin(
      target: 'start:$workspaceId',
      draft: previous.stamp,
    );
    final input = StudioPromptInput(
      inputId: operation.id.value,
      text: previous.input.text,
      attachmentDraftIds: previous.input.attachmentDraftIds,
    );
    _dependencies.attachments.retainRetryFrozen(
      operationId: operation.id,
      draftId: previous.stamp.draftId,
      attachmentIds: input.attachmentDraftIds,
    );
    final retry = FrozenStartSessionSubmission(
      stamp: previous.stamp,
      attachmentStamp: previous.attachmentStamp,
      operation: operation,
      workspaceId: workspaceId,
      project: previous.project,
      route: previous.route,
      delegation: previous.delegation,
      input: input,
      attachments: previous.attachments,
    );
    InputSubmissionObservation? evidence;
    try {
      evidence = registerSubmittedInput(
        dependencies: _dependencies,
        operation: operation,
        inputId: input.inputId,
      );
      _observations.removeWhere((entry) => entry.isCancelled);
      _observations.add(evidence);
    } catch (error) {
      operation.reject(error);
      await _dependencies.attachments.completeFrozen(
        operationId: operation.id,
        accepted: false,
        clearCurrent: false,
        workspaceId: workspaceId,
        threadId: null,
      );
      rethrow;
    }
    final entries = _submissionByWorkspace[workspaceId]!;
    entries.remove(previousInputId);
    entries[input.inputId] = ComposerSubmission(
      inputId: input.inputId,
      text: input.text,
      attachments: previous.attachments,
      phase: ComposerSubmissionPhase.sending,
    );
    _frozenByInput.remove(previousInputId);
    _frozenByInput[input.inputId] = retry;
    _publishSubmissions();
    await _dependencies.attachments.completeFrozen(
      operationId: previous.operation.id,
      accepted: false,
      clearCurrent: false,
      workspaceId: workspaceId,
      threadId: null,
    );
    state = state.copyWith(
      preparations: {
        ...state.preparations,
        workspaceId: NewThreadPreparation(
          workspaceId: workspaceId,
          inputId: input.inputId,
          workspaceMode: retry.project.workspaceMode,
        ),
      },
    );
    return _submit(retry, evidence);
  }

  @override
  Future<void> removeSubmission(String workspaceId, String inputId) {
    final existing = _submissionByWorkspace[workspaceId]?[inputId];
    if (existing == null) return Future<void>.value();
    final active = _removeTasks[inputId];
    if (active != null) return active;
    if (_closed)
      return Future<void>.error(StateError('The start draft is closed'));
    if (existing.phase != ComposerSubmissionPhase.failed) {
      return Future<void>.error(
        StateError('Only failed submissions can be removed'),
      );
    }
    final completion = Completer<void>();
    final task = completion.future;
    _removeTasks[inputId] = task;
    final frozen = _frozenByInput.remove(inputId);
    _submissionByWorkspace[workspaceId]!.remove(inputId);
    if (state.preparations[workspaceId]?.inputId == inputId) {
      state = state.copyWith(
        preparations: {...state.preparations}..remove(workspaceId),
      );
    }
    _publishSubmissions();
    unawaited(
      (frozen == null ? Future<void>.value() : _releaseFrozen(frozen)).then(
        completion.complete,
        onError: completion.completeError,
      ),
    );
    return task;
  }

  void _preparationFailure(
    FrozenStartSessionSubmission frozen,
    Object error, {
    required bool known,
  }) {
    if (_closed) return;
    final current = state.preparations[frozen.workspaceId];
    if (current == null || current.inputId != frozen.input.inputId) return;
    state = state.copyWith(
      preparations: {
        ...state.preparations,
        frozen.workspaceId: current.withFailure(error, known: known),
      },
    );
  }

  void _clearPreparation(FrozenStartSessionSubmission frozen) {
    if (_closed ||
        state.preparations[frozen.workspaceId]?.inputId != frozen.input.inputId)
      return;
    state = state.copyWith(
      preparations: {...state.preparations}..remove(frozen.workspaceId),
    );
  }

  void _failure(
    ComposerThreadState composer,
    FrozenStartSessionSubmission frozen,
    Object error,
  ) {
    if (_closed) return;
    if (state.revision != frozen.stamp.revision ||
        _dependencies.attachments.newThreadStamp(frozen.workspaceId) !=
            frozen.attachmentStamp) {
      _dependencies.attachments
          .newThreadBinding(frozen.workspaceId)
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
    _dependencies.attachments
        .newThreadBinding(frozen.workspaceId)
        .write(
          ComposerThreadState.failure(
            error: error,
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
    final settings = _dependencies.settings.value;
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
    final account = _dependencies
        .modelAccounts()
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

  Future<void> discardProject(String workspaceId) async {
    if (_closed) return;
    _acpGenerations[workspaceId] = (_acpGenerations[workspaceId] ?? 0) + 1;
    state = state.copyWith(
      projects: {...state.projects}..remove(workspaceId),
      preparations: {...state.preparations}..remove(workspaceId),
      acpPreparations: {...state.acpPreparations}..remove(workspaceId),
      revision: state.revision + 1,
    );
    _acpCreatedByWorkspace.remove(workspaceId);
    await prepareAcp(workspaceId);
    await _dependencies.attachments.discardProject(workspaceId);
  }

  Future<void> close() => _closing ??= _close();

  Future<void> _close() async {
    _closed = true;
    for (final waiting in _acpReadyWaits.values) {
      if (!waiting.isCompleted) {
        waiting.completeError(StateError('The start draft is closed'));
      }
    }
    Object? failure;
    StackTrace? failureStack;
    Future<void> waitFor(Iterable<Future<void>> tasks) async {
      try {
        await Future.wait(tasks);
      } catch (error, stackTrace) {
        failure ??= error;
        failureStack ??= stackTrace;
      }
    }

    await waitFor(_pendingByWorkspace.values);
    await waitFor(_acpPreparing.values.map((value) => value.task).toList());
    for (final prepared in _acpPrepared.values.toList()) {
      try {
        final result = await _dependencies.acpSessions!.discardDraft(
          prepared.owner,
        );
        if (!result.localComplete)
          throw StateError('ACP draft cleanup is incomplete');
      } catch (error, stackTrace) {
        failure ??= error;
        failureStack ??= stackTrace;
      }
    }
    await waitFor(_retryByInput.values);
    await waitFor(_removeTasks.values);
    await waitFor(_presentationTasks.values);
    for (final frozen in _frozenByInput.values.toList()) {
      try {
        await _releaseFrozen(frozen);
      } catch (error, stackTrace) {
        failure ??= error;
        failureStack ??= stackTrace;
      }
    }
    _frozenByInput.clear();
    for (final observation in _observations) {
      observation.cancel();
    }
    _observations.clear();
    if (failure != null) Error.throwWithStackTrace(failure!, failureStack!);
  }
}

final class FrozenStartSessionSubmission {
  const FrozenStartSessionSubmission({
    required this.stamp,
    required this.attachmentStamp,
    required this.operation,
    required this.workspaceId,
    required this.project,
    required this.route,
    this.serviceTier,
    required this.delegation,
    required this.input,
    required this.attachments,
  });
  final DraftStamp stamp;
  final DraftStamp attachmentStamp;
  final OperationHandle operation;
  final String workspaceId;
  final StartSessionProjectDraft project;
  final ModeModelRouteView route;
  final String? serviceTier;
  final DelegationSettingsView delegation;
  final StudioPromptInput input;
  final List<AttachmentDraftView> attachments;
}
