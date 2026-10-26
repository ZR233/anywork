import 'dart:async';
import 'dart:convert';

import '../../../drafts.dart' show SubmitPromptReceipt;
import '../../../operations_ports.dart';
import '../../../resources_ports.dart';
import '../../../workspace.dart' show ThreadStatus, WorkspaceThreadRecord;
import '../domain/execution_values.dart';
import '../domain/facet_state.dart';
import '../domain/interaction_index_state.dart';
import '../domain/interaction_values.dart';
import '../domain/interrupt_turn_reply.dart';
import '../domain/read_scopes.dart';
import '../domain/thread_command_reply.dart';
import '../domain/thread_identity.dart';
import '../domain/turn_values.dart';
import 'connection_owner.dart';
import 'conversation_command_port.dart';
import 'conversation_demand.dart';
import 'conversation_observation_port.dart';
import 'interaction_index_owner.dart';
import 'read_scope_owners.dart';
import 'session_context_task.dart';
import 'session_feeds.dart';
import 'session_metadata.dart';
import 'session_reads.dart';
import 'session_scope_access.dart';
import 'session_ui_demand.dart';
import 'thread_mirrors.dart';
import 'timeline_owner.dart';
import 'timeline_port.dart';

part 'session_stop_work.dart';
part 'session_commands.dart';

/// One specific Session, including metadata opens which have not returned yet.
final class ConversationSessionOwner extends ConversationScopeAccess {
  ConversationSessionOwner({
    required this.threadId,
    required this.observationPort,
    required ConversationContextPort contextPort,
    required ResourceBudget budget,
    required ResourcePermit readModelPermit,
    required OperationRecorder operations,
    required TimelineTransport timelinePort,
    required ConversationCommandPort commands,
    required this.nextAttempt,
    required void Function(ConversationSessionOwner) onUnused,
  }) : _contextPort = contextPort,
       _budget = budget,
       _onUnused = onUnused,
       _operations = operations,
       _commands = commands,
       _mirrors = ThreadMirrors(
         threadId: threadId,
         budget: budget,
         operations: operations,
         permit: readModelPermit,
       ),
       _timeline = ConversationTimelineOwner(
         threadId: threadId,
         port: timelinePort,
         budget: budget,
         nextAttempt: nextAttempt,
       ),
       readOwners = ConversationSessionReads(
         threadId: threadId,
         budget: budget,
         nextAttempt: nextAttempt,
       ) {
    _index = ConversationInteractionIndex(
      threadId: threadId,
      budget: budget,
      nextAttempt: nextAttempt,
      openIndex: openIndexReference,
      openInteraction: openInteractionReference,
    );
    _feeds = ConversationSessionFeeds(
      threadId: threadId,
      port: observationPort,
      budget: budget,
      nextAttempt: nextAttempt,
      mirrors: _mirrors,
      onExecution: _handoffExecution,
      onIncarnation: _incarnationChanged,
      onExecutionUnavailable: _index.connecting,
      onSourceIdentity: _sourceIdentity,
      onExecutionAttempt: _executionAttempt,
      onExecutionBaseline: _executionBaseline,
      onExecutionFailure: _executionFailed,
      checkExecutionSource: _checkExecutionSource,
    );
    _metadata = ConversationSessionMetadata(
      threadId: threadId,
      budget: budget,
      nextAttempt: nextAttempt,
      open: () => _contextPort.openThreadMetadata(threadId),
      onValue: (thread) {
        _thread = thread;
      },
    );
    _commandActions = _ConversationCommands(this);
  }
  @override
  final String threadId;
  @override
  final ConversationObservationPort observationPort;
  @override
  final ConversationSessionReads readOwners;
  final ConversationContextPort _contextPort;
  final ResourceBudget _budget;
  final OperationRecorder _operations;
  final ConversationCommandPort _commands;
  final AttemptId Function() nextAttempt;
  final void Function(ConversationSessionOwner) _onUnused;
  final ThreadMirrors _mirrors;
  final ConversationTimelineOwner _timeline;
  late final ConversationSessionFeeds _feeds;
  late final ConversationInteractionIndex _index;
  late final ConversationSessionMetadata _metadata;
  late final _ConversationCommands _commandActions;
  final Set<_ExecutionEvidenceOwner> _evidence = {};
  ConversationContextTask? _contextTask;
  ConversationUiDemand? _uiDemand;
  Completer<void>? _evidenceReleased;
  WorkspaceThreadRecord? _thread;
  ThreadObservationMode? _mode;
  ThreadFacetStamp? _projection;
  CreatedInputExecutionBinding? _executionBinding;
  bool _contextAllowed = false;
  bool _selected = false;
  bool _stopAdmissionRetired = false;
  bool _sealed = false;
  bool _disposed = false;
  int _contextGeneration = 0;
  int _demandGeneration = 0;
  Object? lastCause;
  StackTrace? lastStack;

  @override
  ReadonlyLatestValue<ThreadExecutionState> get execution => _mirrors.execution;
  @override
  ReadonlyLatestValue<ThreadMetricsState> get metrics => _mirrors.metrics;
  @override
  ReadonlyLatestValue<ThreadContextState> get context => _mirrors.context;
  @override
  ReadonlyLatestValue<ThreadConfigurationState> get configuration =>
      _mirrors.configuration;
  @override
  ReadonlyLatestValue<ThreadAuthoringState> get authoring => _mirrors.authoring;
  @override
  ReadonlyLatestValue<InteractionIndexReadState> get interactions =>
      _index.state;
  @override
  ConversationTimelineOwner get timeline => _timeline;
  @override
  bool get readAdmissionClosed =>
      _sealed || !_contextAllowed || _uiDemand == null || _uiDemand!.retired;
  @override
  ConversationUiDemand? get readUiDemand => _uiDemand;
  @override
  ThreadFacetStamp? get currentProjection => _projection;
  _ExecutionIdentity? get _projectionIdentity {
    final source = _projection;
    return source == null
        ? null
        : (runtimeEpoch: source.runtimeEpoch, incarnation: source.incarnation);
  }

  bool get hasEvidenceDemand => _evidence.isNotEmpty;
  bool get isSelected => _selected;
  WorkspaceThreadRecord? get frozenThread => _thread;
  bool get isDisposed => _disposed;
  ConversationUiDemand? get uiDemand => _uiDemand;
  ConversationMetadataBorrow? reserveArchiveMetadata() =>
      _metadata.reserve(allowNew: !_sealed);

  void bindUiDemand(int selectionGeneration) {
    final previous = _uiDemand;
    if (previous?.selectionGeneration == selectionGeneration) return;
    _uiDemand = ConversationUiDemand(selectionGeneration, nextAttempt());
  }

  void retireStopAdmission() {
    _stopAdmissionRetired = true;
  }

  ThreadFacetStamp? _sourceIdentity(
    ThreadFacetStamp source, {
    required bool baseline,
    required bool commit,
  }) {
    if (_sealed) throw conversationCancelled;
    final previous = _projection;
    if (previous != null && source.runtimeEpoch != previous.runtimeEpoch)
      throw const StudioFailure(
        code: StudioFailureCode.runtimeStopped,
        message: 'A Session cannot adopt another runtime epoch.',
        retryable: false,
        correlationId: 'conversation-runtime-identity',
      );
    if (previous != null && source.incarnation < previous.incarnation)
      throw const StudioFailure(
        code: StudioFailureCode.superseded,
        message: 'A late baseline belongs to a replaced projection.',
        retryable: true,
        correlationId: 'conversation-projection-identity',
      );
    if (!baseline &&
        (previous == null || source.incarnation != previous.incarnation))
      throw const StudioFailure(
        code: StudioFailureCode.superseded,
        message: 'A change cannot establish a replacement Session projection.',
        retryable: true,
        correlationId: 'conversation-projection-baseline',
      );
    if (commit) {
      _projection = source;
      for (final lease in List.of(_evidence)) {
        lease._constrain(source);
      }
    }
    return previous;
  }

  void select(bool selected) {
    if (_sealed) {
      if (selected) throw conversationCancelled;
      return;
    }
    if (_selected == selected) return;
    _selected = selected;
    if (!selected) {
      _uiDemand?.retired = true;
      retireStopAdmission();
    }
    if (!selected && _evidence.isEmpty) _contextGeneration++;
    if (_contextAllowed) {
      _applyDemand();
    } else if (selected) {
      _loadContext().ignore();
    }
  }

  bool get _executionDemand => _evidence.any((lease) => lease._needsSource);
  bool get _needsAny => _selected || _executionDemand;

  Future<void> _loadContext() {
    if (_sealed || !_needsAny) return Future.error(conversationCancelled);
    final previous = _contextTask;
    if (previous?.pending == true) return previous!.result;
    final task = ConversationContextTask(
      threadId: threadId,
      attemptId: nextAttempt(),
    );
    _contextTask = task;
    final generation = ++_contextGeneration;
    task.start(
      budget: _budget,
      action: () async {
        for (final facet in ThreadFacet.values) {
          _checkContext(generation);
          if ((_selected || facet == ThreadFacet.execution) &&
              (facet != ThreadFacet.execution || !_hasCreatedExecution)) {
            _mirrors.synchronize(
              facet,
              const FacetSyncState(phase: FacetSyncPhase.connecting),
            );
          }
        }
        await _resolveContext(generation);
      },
      onFailure: (error, stack) {
        lastCause = error;
        lastStack = stack;
        if (!_sealed && generation == _contextGeneration)
          _contextFailed(error, stack);
      },
    );
    return task.result;
  }

  void _checkContext(int generation) {
    if (_sealed || !_needsAny || generation != _contextGeneration)
      throw conversationCancelled;
  }

  Future<void> _resolveContext(int generation) async {
    _checkContext(generation);
    final thread = await _metadata.readForUi();
    _checkContext(generation);
    if (thread.id != threadId)
      throw const StudioFailure(
        code: StudioFailureCode.protocol,
        message: 'The metadata read returned another Thread.',
        retryable: false,
        correlationId: 'conversation-context-identity',
      );
    final access = await _contextPort.readRecoveryAccess(thread);
    _checkContext(generation);
    switch (access) {
      case BlockedConversationRecovery(:final error):
        throw error;
      case UnknownConversationRecovery(:final error):
        throw error ??
            const StudioFailure(
              code: StudioFailureCode.unavailable,
              message: 'The original Thread recovery access is unknown.',
              retryable: true,
              correlationId: 'conversation-recovery-unknown',
            );
      case AllowedConversationRecovery():
        break;
    }
    // Child agent Threads observe a cold checkpoint: a planner never runs as a
    // live UI observation, and a closed child has no live owner to subscribe to.
    // Root Threads and running children stay live.
    _mode =
        thread.parentThreadId != null &&
            (thread.role == 'planner' || thread.status == ThreadStatus.closed)
        ? ThreadObservationMode.cold
        : ThreadObservationMode.live;
    _contextAllowed = true;
    _applyDemand();
  }

  void _contextFailed(Object error, StackTrace stack) {
    lastCause = error;
    lastStack = stack;
    if (_sealed) return;
    final failure = conversationFailure(error);
    for (final facet in ThreadFacet.values) {
      if ((_selected || facet == ThreadFacet.execution) &&
          (facet != ThreadFacet.execution || !_hasCreatedExecution)) {
        _mirrors.synchronize(
          facet,
          FacetSyncState(phase: FacetSyncPhase.failed, error: failure),
        );
      }
    }
  }

  void _applyDemand({CreatedInputExecutionBinding? executionSource}) {
    if (_sealed) return;
    final mode = _mode ?? ThreadObservationMode.live;
    final ui = _selected && _contextAllowed;
    final generation = ++_demandGeneration;
    bool current() => !_sealed && generation == _demandGeneration;
    // Preserve the active binding before its first baseline, including during
    // reentrant failure notifications from leases of the retiring attempt.
    _feeds.demand(
      selected: ui,
      evidence: _executionDemand,
      mode: mode,
      isCurrent: current,
      executionSource:
          executionSource ??
          (_feeds.executionAttemptId != null
              ? _executionBinding
              : _wantedCreatedSource),
    );
    if (!current()) return;
    _timeline.setDemand(ui);
  }

  CreatedInputExecutionBinding? get _wantedCreatedSource {
    for (final lease in _evidence) {
      if (lease._needsSource && lease._created != null) return lease._created;
    }
    return null;
  }

  bool get _hasCreatedExecution =>
      _executionBinding != null || _wantedCreatedSource != null;
  @override
  Future<void> retry(ThreadFacet facet) {
    if (_sealed || !_needsAny) return Future.error(conversationCancelled);
    if (!_contextAllowed) return _loadContext();
    // An explicit retry always re-establishes the original facet source and
    // waits for its fresh baseline; a retained canonical value never stands in
    // for the requested new attempt.
    if (facet == ThreadFacet.execution) {
      final previous = _feeds.executionAttemptId;
      _applyDemand();
      if (_feeds.executionAttemptId != null &&
          _feeds.executionAttemptId != previous)
        return Future.value();
    }
    return _feeds.retry(facet);
  }

  @override
  Future<void> loadInteractionsPage({int limit = 32}) {
    if (readAdmissionClosed) return Future.error(conversationCancelled);
    return _index.load(limit: limit);
  }

  @override
  OperationTicket<Unit> compactThread({required ThreadFacetStamp origin}) =>
      _commandActions.compact(origin);
  @override
  OperationTicket<CommitReceipt> setThreadMode({
    required ThreadFacetStamp origin,
    required String mode,
  }) => _commandActions.setMode(origin, mode);
  @override
  OperationTicket<ThreadModelRouteCommandReply> setThreadModelRoute({
    required ThreadFacetStamp origin,
    OperationId? operationId,
    required String accountId,
    required String modelId,
    String? effort,
    required int expectedModelRouteRevision,
    required int expectedSettingsRevision,
  }) => _commandActions.setRoute(
    origin,
    accountId,
    modelId,
    effort,
    expectedModelRouteRevision,
    expectedSettingsRevision,
    operationId: operationId,
  );
  @override
  OperationTicket<InteractionCommandReply> respondInteraction({
    required ThreadFacetStamp origin,
    OperationId? operationId,
    required String interactionId,
    required int expectedInteractionRevision,
    required InteractionResolutionCommand resolution,
  }) => _commandActions.respond(
    origin,
    interactionId,
    expectedInteractionRevision,
    resolution,
    operationId: operationId,
  );

  @override
  OperationTicket<Unit> stopTurn({
    required ThreadFacetStamp origin,
    required TurnReadRef target,
  }) {
    final binding = _executionBinding;
    final originalAttempt = _feeds.executionAttemptId;
    final writer = _operations.begin<Unit>(
      target: 'stop:$threadId',
      requireIdentityObservation: true,
    );
    final work = _StopTurnWork(
      session: this,
      writer: writer,
      origin: origin,
      target: target,
      binding: binding,
      originalAttempt: originalAttempt,
    );
    if (_evidence.isEmpty) _evidenceReleased = Completer<void>();
    _evidence.add(work);
    work.start();
    return writer.ticket;
  }

  SubmissionExecutionLease retainForSubmission({
    required ThreadFacetStamp expectedOrigin,
  }) {
    if (_sealed) throw conversationCancelled;
    if (expectedOrigin.facet != ThreadFacet.execution)
      throw _submissionConflict;
    if (readAdmissionClosed) throw _submissionConflict;
    final stamp = _readyExecutionStamp;
    if (stamp == null) throw _submissionConflict;
    if (!_sameProjection(expectedOrigin, stamp)) throw _submissionSuperseded;
    return _retainSubmission(stamp: stamp);
  }

  SubmissionExecutionLease retainForCreatedInput({
    required SubmitPromptReceipt receipt,
    required CreatedInputExecutionBinding binding,
  }) {
    if (_sealed) throw conversationCancelled;
    if (receipt.threadId != threadId) throw _submissionConflict;
    if (receipt.inputId.trim().isEmpty ||
        receipt.cursor < 0 ||
        !_receiptDigest.hasMatch(receipt.requestDigest)) {
      throw const StudioFailure(
        code: StudioFailureCode.protocol,
        message: 'Created-input observation requires a valid native acceptance receipt.',
        retryable: false,
        correlationId: 'created-input-receipt',
      );
    }
    if (binding.threadId != threadId || binding.inputId != receipt.inputId)
      throw _submissionConflict;
    if (binding.runtimeEpoch.isEmpty || binding.incarnation < 1)
      throw const StudioFailure(
        code: StudioFailureCode.protocol,
        message: 'The created-input source identity is invalid.',
        retryable: false,
        correlationId: 'created-input-source',
      );
    final projection = _projection;
    if (projection != null && !binding.matches(projection))
      throw _submissionSuperseded;
    final stamp = identical(_executionBinding?.source, binding.source)
        ? _readyExecutionStamp
        : null;
    for (final lease in _evidence) {
      final origin = lease._source;
      if (origin != null &&
          (origin.runtimeEpoch != binding.runtimeEpoch ||
              origin.incarnation != binding.incarnation))
        throw _submissionSuperseded;
    }
    return _retainSubmission(stamp: stamp, created: binding);
  }

  ThreadFacetStamp? get _readyExecutionStamp {
    final stamp = execution.value.stamp;
    final projection = _projection;
    return !_sealed &&
            _feeds.executionHasBaseline &&
            execution.value.sync.phase == FacetSyncPhase.ready &&
            execution.value.value != null &&
            stamp != null &&
            stamp.facet == ThreadFacet.execution &&
            projection != null &&
            _sameProjection(stamp, projection)
        ? stamp
        : null;
  }

  SubmissionExecutionLease _retainSubmission({
    required ThreadFacetStamp? stamp,
    CreatedInputExecutionBinding? created,
  }) {
    if (_evidence.isEmpty) _evidenceReleased = Completer<void>();
    final lease = _SubmissionExecutionLease(
      threadId: threadId,
      attemptId: nextAttempt(),
      execution: execution,
      source: created == null
          ? _projectionIdentity
          : (
              runtimeEpoch: created.runtimeEpoch,
              incarnation: created.incarnation,
            ),
      created: created,
      readOwners: readOwners,
      observationPort: observationPort,
      release: _releaseEvidence,
    );
    _evidence.add(lease);
    final attempt = _feeds.executionAttemptId;
    final sameSource =
        created == null || identical(_executionBinding?.source, created.source);
    if (attempt != null && sameSource && (stamp != null || created != null)) {
      lease._bind(attempt, _executionBinding);
      if (stamp != null) lease._complete(attempt, stamp);
    }
    try {
      // A created lease requests this exact source even when an ordinary or
      // differently bound attempt already has a same-incarnation baseline.
      _applyDemand(executionSource: created);
      // An unchanged source key may be between attempts. This new demand still
      // needs its own real attempt; it cannot complete from the old latest.
      if (created != null &&
          lease._needsSource &&
          _feeds.executionAttemptId == null) {
        _feeds
            .retry(ThreadFacet.execution)
            .then<void>(
              (_) {},
              onError: (Object error, StackTrace stack) {
                lastCause = error;
                lastStack = stack;
                lease._fail(conversationFailure(error), stack, error);
              },
            )
            .ignore();
      }
    } catch (error, stack) {
      lastCause = error;
      lastStack = stack;
      // Admission already transferred this lease. Return its failed ready and
      // release capability even when a synchronous notification failed.
      lease._fail(conversationFailure(error), stack, error);
    }
    return lease;
  }

  void _releaseEvidence(_ExecutionEvidenceOwner lease) {
    if (!_evidence.remove(lease)) return;
    if (_evidence.isEmpty) {
      _evidenceReleased?.complete();
      _evidenceReleased = null;
    }
    if (!_selected && !_executionDemand) _contextGeneration++;
    try {
      if (!_sealed) _applyDemand();
    } finally {
      if (!_selected && _evidence.isEmpty) _onUnused(this);
    }
  }

  void _executionAttempt(
    AttemptId attempt,
    CreatedInputExecutionBinding? binding,
  ) {
    if (_feeds.executionAttemptId != attempt) throw _submissionSuperseded;
    _executionBinding = binding;
    var changed = false;
    for (final lease in List.of(_evidence)) {
      // A failure callback may synchronously replace this attempt. Its newer
      // announcement owns the remaining binding/invalidations. Throwing also
      // prevents this superseded opener from beginning over its newer sibling.
      if (_feeds.executionAttemptId != attempt) throw _submissionSuperseded;
      changed = lease._bind(attempt, binding) || changed;
    }
    if (_feeds.executionAttemptId != attempt) throw _submissionSuperseded;
    if (changed) _applyDemand();
    if (_feeds.executionAttemptId != attempt) throw _submissionSuperseded;
  }

  Future<void> _handoffExecution(
    AttemptId attempt,
    ThreadFacetStamp stamp,
    InteractionIndexHeader index,
    InteractionDelta? delta,
    TurnBrief? active,
    List<TurnBrief> turns,
  ) async {
    _index.adopt(stamp, index, delta);
    // Every admitted consumer registers its work synchronously in its original
    // lease. A sibling/history completion cannot release an in-flight handoff.
    try {
      await Future.wait([
        for (final lease in List.of(_evidence))
          lease._handoff(attempt, stamp, active, turns),
      ]);
    } catch (error, stack) {
      lastCause = error;
      lastStack = stack;
      rethrow;
    }
  }

  void _executionBaseline(AttemptId attempt, ThreadFacetStamp stamp) {
    if (_sealed ||
        _feeds.executionAttemptId != attempt ||
        _readyExecutionStamp == null)
      return;
    var changed = false;
    for (final lease in List.of(_evidence)) {
      changed = lease._complete(attempt, stamp) || changed;
    }
    if (changed) _applyDemand();
  }

  void _executionFailed(StudioFailure error) {
    var changed = false;
    for (final lease in List.of(_evidence)) {
      changed = lease._fail(error) || changed;
    }
    if (changed || (_executionBinding != null && _wantedCreatedSource == null))
      _applyDemand();
  }

  void _checkExecutionSource(ThreadFacetStamp stamp) {
    final binding = _executionBinding;
    if (binding != null &&
        (stamp.facet != ThreadFacet.execution || !binding.matches(stamp))) {
      throw _submissionSuperseded;
    }
  }

  void _incarnationChanged(ThreadFacetStamp previous) {
    var changed = false;
    for (final lease in List.of(_evidence)) {
      if (lease._source case final source?
          when _matchesIdentity(source, previous)) {
        changed = lease._fail(_submissionSuperseded) || changed;
      }
    }
    try {
      readOwners.retireOrigin(previous);
    } finally {
      if (changed) _applyDemand();
    }
  }

  Future<CloseReport> retireUi({DateTime? deadline}) =>
      closeRetiredUi(_uiDemand, deadline: deadline);
  void requestRetireUi(ConversationUiDemand? demand) {
    if (demand == null) return;
    demand.retired = true;
    if (!identical(_uiDemand, demand) || demand.retirementRequested) return;
    demand.retirementRequested = true;
    retireStopAdmission();
    _selected = false;
    _contextGeneration++;
  }

  Future<CloseReport> closeRetiredUi(
    ConversationUiDemand? demand, {
    DateTime? deadline,
    bool retry = false,
  }) {
    if (demand == null) return Future.value(CloseReport(unresolved: []));
    requestRetireUi(demand);
    final current = identical(_uiDemand, demand);
    final context = _contextTask;
    if (current && !_sealed && !demand.withdrawn) {
      demand.withdrawn = true;
      try {
        _applyDemand();
      } catch (error, stack) {
        demand.recordFailure('conversationUiDemand', error, stack);
      }
    }
    return closeConversationUi(
      threadId: threadId,
      demand: demand,
      isCurrent: () => identical(_uiDemand, demand),
      closeScopes: () =>
          readOwners.closeUi(demand, deadline: deadline, retry: retry),
      close: [
        if (current)
          () => _feeds.retireUi(
            // An admitted operation lease owns its execution source until it
            // releases it; opening it was only one step of that ownership. An
            // archive retirement therefore must never close the source an
            // operation still reads its Turns from.
            retainExecution: _evidence.isNotEmpty,
            deadline: deadline,
            retry: retry,
          ),
        if (current) () => _timeline.close(deadline: deadline, retry: retry),
        if (current) () => _index.close(deadline: deadline, retry: retry),
        if (current) () => _metadata.close(deadline: deadline, retry: retry),
        if (current && context != null) () => context.close(deadline: deadline),
      ],
    );
  }

  void seal() {
    if (_sealed) return;
    _sealed = true;
    _selected = false;
    _contextGeneration++;
    _uiDemand?.retired = true;
    _commandActions.seal();
    for (final lease in List.of(_evidence)) {
      lease._fail(conversationCancelled);
    }
    _feeds.seal();
    _timeline.seal();
    _index.seal();
    readOwners.seal();
    _metadata.seal();
  }

  Future<CloseReport> retryCleanup({DateTime? deadline}) async {
    if (_sealed) return close(deadline: deadline, retry: true);
    final demand = _uiDemand;
    final stops = _evidence
        .whereType<_StopTurnWork>()
        .where((work) => work._canFinish)
        .toList();
    // Cleanup admission comes from the original owners, not from the current
    // selection or an uncompleted operation's ordinary pending state.
    final reports = await Future.wait([
      if (demand?.retirementRequested == true)
        closeRetiredUi(demand, deadline: deadline, retry: true)
      else ...[
        _feeds.joinRetired(deadline: deadline, retry: true),
        _timeline.retryCleanup(deadline: deadline),
        _metadata.retryCleanup(deadline: deadline),
      ],
      readOwners.retryCleanup(
        deadline: deadline,
        joinedEvidence: stops.toSet(),
        joinedUi: demand?.retirementRequested == true ? demand : null,
      ),
      for (final work in stops) work.close(deadline: deadline, retry: true),
    ]);
    return conversationCloseReport([
      for (final report in reports) ...report.unresolved,
    ]);
  }

  Future<CloseReport> close({DateTime? deadline, bool retry = false}) async {
    seal();
    final stops = List.of(_evidence)
        .whereType<_StopTurnWork>()
        .toList(growable: false);
    final closing = Future.wait([
      _commandActions.close(deadline: deadline, retry: retry),
      _feeds.close(deadline: deadline, retry: retry),
      _timeline.close(deadline: deadline, retry: retry),
      _index.close(deadline: deadline, retry: retry),
      readOwners.close(
        deadline: deadline,
        retry: retry,
        joinedEvidence: stops.toSet(),
      ),
      _metadata.close(deadline: deadline, retry: retry),
      if (_contextTask case final context?) context.close(deadline: deadline),
      for (final work in stops) work.close(deadline: deadline, retry: retry),
    ]);
    closing.ignore();
    final settled = Future.wait([
      if (_evidenceReleased case final evidence?) evidence.future,
    ]).then<void>((_) {});
    await observeConversationCompletion(settled, deadline);
    final reports = await closing;
    final unresolved = [
      for (final report in reports) ...report.unresolved,
      if (_uiDemand case final demand?) ...demand.report(threadId).unresolved,
      for (final lease in _evidence)
        UnresolvedResource(
          owner: 'conversation-evidence:$threadId',
          attemptId: lease.attemptId,
          issues: [_pendingIssue('operationDemandPending')],
        ),
    ];
    if (unresolved.isEmpty && !_disposed) {
      _disposed = true;
      _mirrors.dispose();
    }
    return conversationCloseReport(unresolved);
  }

  FeedCloseIssue _pendingIssue(String code) => FeedCloseIssue(
    diagnostic: StudioShutdownIssue(
      stage: 'conversationSession',
      code: code,
      message: 'The original Session work is still owned and in flight.',
      retryable: true,
      correlationId: 'conversation-session',
    ),
    recovery: CleanupRecovery.awaitCompletion,
  );
}

const _submissionConflict = StudioFailure(
  code: StudioFailureCode.conflict,
  message: 'Submission requires the original ready execution source.',
  retryable: false,
  correlationId: 'submission-execution-source',
);
const _submissionSuperseded = StudioFailure(
  code: StudioFailureCode.superseded,
  message: 'The original submission execution source has been replaced.',
  retryable: false,
  correlationId: 'submission-execution-superseded',
);
final _receiptDigest = RegExp(r'^sha256:[0-9a-f]{64}$');
bool _sameProjection(ThreadFacetStamp a, ThreadFacetStamp b) =>
    a.runtimeEpoch == b.runtimeEpoch && a.incarnation == b.incarnation;
typedef _ExecutionIdentity = ({String runtimeEpoch, int incarnation});
bool _matchesIdentity(_ExecutionIdentity a, ThreadFacetStamp b) =>
    a.runtimeEpoch == b.runtimeEpoch && a.incarnation == b.incarnation;

/// Mechanical ownership shared by original input evidence and exact Stop work.
/// Only the submission adapter below exposes the composition-only input lease.
class _ExecutionEvidenceOwner {
  _ExecutionEvidenceOwner({
    required this.threadId,
    required this.attemptId,
    required this.execution,
    required _ExecutionIdentity? source,
    required CreatedInputExecutionBinding? created,
    required ConversationSessionReads readOwners,
    required ConversationObservationPort observationPort,
    required void Function(_ExecutionEvidenceOwner) release,
  }) : _source = source,
       _created = created,
       _readOwners = readOwners,
       _observationPort = observationPort,
       _release = release {
    _ready.future.ignore();
  }
  final String threadId;
  final AttemptId attemptId;
  final ReadonlyLatestValue<ThreadExecutionState> execution;
  final ConversationSessionReads _readOwners;
  final ConversationObservationPort _observationPort;
  final void Function(_ExecutionEvidenceOwner) _release;
  final Completer<ThreadFacetStamp> _ready = Completer<ThreadFacetStamp>();
  final Set<Future<void>> _handoffs = {};
  final Map<String, FeedCloseIssue> _notificationFailures = {};
  final Map<String, ({Object cause, StackTrace stack})> _notificationCauses =
      {};
  Future<void>? _turnReadJoin;
  Completer<void>? _notifyingFailure;
  Future<void> Function(ThreadFacetStamp, TurnBrief?, List<TurnBrief>)?
  _consume;
  void Function(StudioFailure)? _onFailure;
  _ExecutionIdentity? _source;
  final CreatedInputExecutionBinding? _created;
  AttemptId? _sourceAttempt;
  ThreadFacetStamp? _handoffOrigin;
  List<TurnBrief> _handoffTurns = const [];
  StudioFailure? _sourceFailure;
  Object? lastCause;
  StackTrace? lastStack;
  bool _needsSource = true;
  bool _released = false;
  bool _releaseRequested = false;
  bool _turnReadsClosed = false;
  bool _turnReadsSealRequested = false;
  bool _failureNotified = false;
  Future<ThreadFacetStamp> get ready => _ready.future;
  void _bindConsumer({
    required Future<void> Function(
      ThreadFacetStamp,
      TurnBrief?,
      List<TurnBrief>,
    )
    consume,
    required void Function(StudioFailure) onFailure,
  }) {
    if (_released ||
        (_turnReadsClosed || _turnReadsSealRequested) && _sourceFailure == null)
      throw conversationCancelled;
    if (_consume != null)
      throw const StudioFailure(
        code: StudioFailureCode.conflict,
        message: 'The original submission already has an execution consumer.',
        retryable: false,
        correlationId: 'submission-execution-consumer',
      );
    _consume = consume;
    _onFailure = onFailure;
    _notifyFailure();
  }

  Future<void> _handoff(
    AttemptId attempt,
    ThreadFacetStamp origin,
    TurnBrief? active,
    List<TurnBrief> turns,
  ) {
    final consume = _consume;
    // Only an accepted handoff may enter. A pending seal no longer cancels the
    // handoff the Session already admitted.
    if (_released || _turnReadsSealRequested || consume == null)
      return Future.value();
    final source = _source;
    if (_sourceAttempt != attempt ||
        source == null ||
        !_matchesIdentity(source, origin) ||
        origin.facet != ThreadFacet.execution) {
      _fail(_submissionSuperseded);
      return Future.error(_submissionSuperseded);
    }
    if (_handoffOrigin != null)
      return Future.error(
        const StudioFailure(
          code: StudioFailureCode.conflict,
          message: 'The original submission handoff is already in flight.',
          retryable: false,
          correlationId: 'submission-execution-handoff',
        ),
      );
    final completion = Completer<void>();
    _handoffs.add(completion.future);
    _handoffOrigin = origin;
    _handoffTurns = turns;
    return Future<void>.sync(() => consume(origin, active, turns)).then<void>(
      (_) {
        _finishHandoff(completion);
      },
      onError: (Object error, StackTrace stack) {
        try {
          _fail(conversationFailure(error), stack, error);
        } finally {
          _finishHandoff(completion);
        }
        Error.throwWithStackTrace(error, stack);
      },
    );
  }

  void _finishHandoff(Completer<void> completion) {
    _handoffOrigin = null;
    _handoffTurns = const [];
    _handoffs.remove(completion.future);
    completion.complete();
    _applyTurnReadSeal();
  }

  bool _acceptsTurn(ThreadFacetStamp origin, TurnReadRef reference) =>
      _turnReadAdmission &&
      _handoffOrigin == origin &&
      _source != null &&
      _matchesIdentity(_source!, origin) &&
      _handoffTurns.any(
        (turn) =>
            turn.reference == reference && turn.revision == reference.revision,
      ) &&
      reference.entry >= 0 &&
      reference.revision >= 0;

  /// A seal request admits no new handoff, yet it never revokes the Turn
  /// identity read of a handoff the Session already accepted. That read owns its
  /// own scope and closes it before the seal applies.
  bool get _turnReadAdmission =>
      !_released &&
      !_turnReadsClosed &&
      (!_turnReadsSealRequested || _handoffs.isNotEmpty);

  Future<TurnReadScope> openTurn(
    TurnReadRef reference, {
    required ThreadFacetStamp origin,
  }) {
    if (!_turnReadAdmission) throw conversationCancelled;
    if (!_acceptsTurn(origin, reference)) throw _submissionSuperseded;
    return _readOwners.openExecutionTurn(
      evidence: this,
      origin: origin,
      reference: reference,
      accepts: () => _acceptsTurn(origin, reference),
      open: () =>
          _observationPort.openTurnRead(threadId, reference, origin: origin),
    );
  }

  void requestCloseTurnReads() {
    _turnReadsSealRequested = true;
    _applyTurnReadSeal();
  }

  /// The seal itself is deferred until every accepted handoff settled, so an
  /// admitted frame is never turned into a cancelled Turn query. The deferral
  /// keeps one execution context: the last handoff completion applies it.
  void _applyTurnReadSeal() {
    if (!_turnReadsSealRequested || _turnReadsClosed) return;
    if (_handoffs.isNotEmpty) return;
    _turnReadsClosed = true;
    _readOwners.requestCloseEvidence(this);
  }

  Future<CloseReport> closeTurnReads({
    DateTime? deadline,
    bool retry = false,
  }) async {
    final joining = _joinTurnReads(retry: retry);
    await observeConversationCompletion(joining, deadline);
    final report = _turnReadReport();
    if (report.complete && _releaseRequested) _finishRelease();
    return report;
  }

  Future<void> _joinTurnReads({required bool retry}) {
    if (_turnReadJoin case final current?) return current;
    final completion = Completer<void>();
    _turnReadJoin = completion.future;
    // A retry joins a notification already running at entry; it must not call
    // that callback again if it later throws during this same close pass.
    final retryNotification =
        retry && _notificationFailures.containsKey('submissionEvidenceFailure');
    unawaited(
      Future<void>.sync(() async {
        requestCloseTurnReads();
        // Joining an already-opened evidence handle must never wait for the
        // handoff that this same close joins: a pending header read would
        // otherwise keep its own native close from starting. Only the native
        // join starts here; the admission seal below still waits for the
        // admitted reads to settle, and a still-opening handle is left to it.
        _readOwners.requestNativeCloseEvidence(this);
        if (retryNotification) _notifyFailure(retry: true);
        final notification = _notifyingFailure?.future;
        // Accepted handoffs settle before their Turn reads are closed: each one
        // owns and closes its own scope, and only then does this same context
        // apply the seal.
        await Future.wait(List.of(_handoffs));
        _applyTurnReadSeal();
        final closing = _readOwners.closeEvidence(this, retry: retry);
        closing.ignore();
        if (notification != null) await notification;
        final report = await closing;
        if (report.complete)
          _notificationFailures.remove('submissionTurnReadClose');
      }).then<void>(
        (_) {
          _turnReadJoin = null;
          completion.complete();
        },
        onError: (Object error, StackTrace stack) {
          _recordNotificationFailure('submissionTurnReadClose', error, stack);
          _turnReadJoin = null;
          completion.complete();
        },
      ),
    );
    return completion.future;
  }

  CloseReport _turnReadReport() {
    final report = _readOwners.evidenceReport(this);
    return conversationCloseReport([
      ...report.unresolved,
      if (_handoffs.isNotEmpty ||
          _turnReadJoin != null ||
          _notifyingFailure != null ||
          _notificationFailures.isNotEmpty)
        UnresolvedResource(
          owner: 'submission-turn-reads:$threadId',
          attemptId: attemptId,
          issues: [
            ..._notificationFailures.values,
            if (_handoffs.isNotEmpty ||
                _turnReadJoin != null ||
                _notifyingFailure != null)
              const FeedCloseIssue(
                diagnostic: StudioShutdownIssue(
                  stage: 'submissionTurnHandoff',
                  code: 'handoffPending',
                  message: 'The original execution handoff, notification or read close is still in flight.',
                  retryable: true,
                  correlationId: 'submission-execution-handoff',
                ),
                recovery: CleanupRecovery.awaitCompletion,
              ),
          ],
        ),
    ]);
  }

  void _constrain(ThreadFacetStamp source) {
    if (!_released && !_ready.isCompleted)
      _source ??= (
        runtimeEpoch: source.runtimeEpoch,
        incarnation: source.incarnation,
      );
  }

  bool _bind(AttemptId attempt, CreatedInputExecutionBinding? binding) {
    if (_released || _sourceFailure != null) return false;
    if (_created != null && !identical(_created.source, binding?.source))
      return _fail(_submissionSuperseded);
    if (_sourceAttempt != null && _sourceAttempt != attempt)
      return _fail(_submissionSuperseded);
    _sourceAttempt = attempt;
    return false;
  }

  bool _complete(AttemptId attempt, ThreadFacetStamp stamp) {
    if (_released || _ready.isCompleted || _sourceAttempt != attempt)
      return false;
    final source = _source;
    if (source != null && !_matchesIdentity(source, stamp))
      return _fail(_submissionSuperseded);
    _source = (
      runtimeEpoch: stamp.runtimeEpoch,
      incarnation: stamp.incarnation,
    );
    _ready.complete(stamp);
    return false;
  }

  bool _fail(StudioFailure error, [StackTrace? stack, Object? cause]) {
    if (_released || _sourceFailure != null) return false;
    _sourceFailure = error;
    lastCause = cause ?? error;
    lastStack = stack;
    final changed = _needsSource;
    _needsSource = false;
    if (!_ready.isCompleted) _ready.completeError(error, stack);
    try {
      requestCloseTurnReads();
    } catch (closeError, closeStack) {
      _recordNotificationFailure(
        'submissionTurnReadClose',
        closeError,
        closeStack,
      );
    }
    _notifyFailure();
    return changed;
  }

  void _notifyFailure({bool retry = false}) {
    final failure = _sourceFailure;
    final notify = _onFailure;
    if (_failureNotified ||
        _notifyingFailure != null ||
        failure == null ||
        notify == null ||
        !retry &&
            _notificationFailures.containsKey('submissionEvidenceFailure'))
      return;
    final completion = Completer<void>();
    _notifyingFailure = completion;
    try {
      notify(failure);
      _failureNotified = true;
      _notificationFailures.remove('submissionEvidenceFailure');
    } catch (error, stack) {
      _recordNotificationFailure('submissionEvidenceFailure', error, stack);
    } finally {
      _notifyingFailure = null;
      completion.complete();
    }
  }

  void _recordNotificationFailure(
    String stage,
    Object error,
    StackTrace stack,
  ) {
    _notificationCauses.putIfAbsent(stage, () => (cause: error, stack: stack));
    _notificationFailures[stage] = conversationIssue(
      stage,
      error,
      CleanupRecovery.retryClose,
    );
  }

  void release() {
    if (_released) return;
    _releaseRequested = true;
    _needsSource = false;
    if (!_ready.isCompleted) _ready.completeError(conversationCancelled);
    requestCloseTurnReads();
    // Legacy read-ready-only borrowers have no scopes/consumer to join and
    // retain their synchronous release. A real read must be verified Clean.
    if (_handoffs.isEmpty &&
        _turnReadJoin == null &&
        _notifyingFailure == null &&
        !_readOwners.hasEvidenceReads(this) &&
        _notificationFailures.isEmpty) {
      _finishRelease();
    } else {
      closeTurnReads().then((report) {
        if (report.complete) _finishRelease();
      }).ignore();
    }
  }

  void _finishRelease() {
    if (_released) return;
    _released = true;
    _release(this);
  }
}

final class _SubmissionExecutionLease extends _ExecutionEvidenceOwner
    implements SubmissionExecutionLease {
  _SubmissionExecutionLease({
    required super.threadId,
    required super.attemptId,
    required super.execution,
    required super.source,
    required super.created,
    required super.readOwners,
    required super.observationPort,
    required super.release,
  });

  @override
  void bindExecutionTurns({
    required Future<void> Function(
      SubmissionExecutionLease,
      ThreadFacetStamp,
      List<TurnBrief>,
    )
    consume,
    required void Function(StudioFailure) onFailure,
  }) => _bindConsumer(
    consume: (origin, _, turns) => consume(this, origin, turns),
    onFailure: onFailure,
  );

  @override
  bool get sourceSuperseded => _sourceFailure != null;
}
