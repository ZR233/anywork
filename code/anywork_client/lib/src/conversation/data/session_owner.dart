import 'dart:async';

import '../../../drafts.dart' show SubmitPromptReceipt;
import '../../../operations_ports.dart';
import '../../../resources.dart';
import '../../../resources_ports.dart';
import '../../../workspace.dart' show WorkspaceThreadRecord;
import '../domain/facet_state.dart';
import '../domain/interaction_index_state.dart';
import '../domain/thread_identity.dart';
import 'connection_owner.dart';
import 'conversation_demand.dart';
import 'conversation_observation_port.dart';
import 'interaction_index_owner.dart';
import 'session_context_task.dart';
import 'session_feeds.dart';
import 'session_metadata.dart';
import 'session_reads.dart';
import 'session_scope_access.dart';
import 'session_ui_demand.dart';
import 'thread_mirrors.dart';
import 'timeline_owner.dart';
import 'timeline_port.dart';

/// One specific Session, including metadata opens which have not returned yet.
final class ConversationSessionOwner extends ConversationScopeAccess {
  ConversationSessionOwner({required this.threadId, required this.observationPort,
    required ConversationContextPort contextPort, required ResourceBudget budget,
    required ResourcePermit readModelPermit,
    required OperationRecorder operations, required TimelineTransport timelinePort,
    required this.nextAttempt, required void Function(ConversationSessionOwner) onUnused})
      : _contextPort = contextPort, _budget = budget, _onUnused = onUnused,
        _mirrors = ThreadMirrors(threadId: threadId, budget: budget, operations: operations, permit: readModelPermit),
        _timeline = ConversationTimelineOwner(threadId: threadId, port: timelinePort,
          budget: budget, nextAttempt: nextAttempt),
        readOwners = ConversationSessionReads(threadId: threadId, budget: budget, nextAttempt: nextAttempt) {
    _index = ConversationInteractionIndex(threadId: threadId, budget: budget,
      nextAttempt: nextAttempt, openIndex: openIndexReference, openInteraction: openInteractionReference);
    _feeds = ConversationSessionFeeds(threadId: threadId, port: observationPort, budget: budget,
      nextAttempt: nextAttempt, mirrors: _mirrors, onExecution: _index.adopt,
      onIncarnation: _incarnationChanged, onExecutionUnavailable: _index.connecting,
      onSourceIdentity: _sourceIdentity, onExecutionAttempt: _executionAttempt,
      onExecutionBaseline: _executionBaseline, onExecutionFailure: _executionFailed,
      checkExecutionSource: _checkExecutionSource);
    _metadata = ConversationSessionMetadata(threadId: threadId, budget: budget, nextAttempt: nextAttempt,
      open: () => _contextPort.openThreadMetadata(threadId), onValue: (thread) { _thread = thread; });
  }
  @override
  final String threadId;
  @override
  final ConversationObservationPort observationPort;
  @override
  final ConversationSessionReads readOwners;
  final ConversationContextPort _contextPort;
  final ResourceBudget _budget;
  final AttemptId Function() nextAttempt;
  final void Function(ConversationSessionOwner) _onUnused;
  final ThreadMirrors _mirrors;
  final ConversationTimelineOwner _timeline;
  late final ConversationSessionFeeds _feeds;
  late final ConversationInteractionIndex _index;
  late final ConversationSessionMetadata _metadata;
  final Set<_SubmissionExecutionLease> _evidence = {};
  ConversationContextTask? _contextTask;
  ConversationUiDemand? _uiDemand;
  Completer<void>? _evidenceReleased;
  WorkspaceThreadRecord? _thread;
  ThreadObservationMode? _mode;
  ThreadFacetStamp? _projection;
  CreatedInputExecutionBinding? _executionBinding;
  bool _contextAllowed = false;
  bool _selected = false;
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
  ReadonlyLatestValue<ThreadConfigurationState> get configuration => _mirrors.configuration;
  @override
  ReadonlyLatestValue<ThreadAuthoringState> get authoring => _mirrors.authoring;
  @override
  ReadonlyLatestValue<InteractionIndexReadState> get interactions => _index.state;
  @override
  ConversationTimelineOwner get timeline => _timeline;
  @override
  bool get readAdmissionClosed => _sealed || !_contextAllowed || _uiDemand == null || _uiDemand!.retired;
  @override
  ConversationUiDemand? get readUiDemand => _uiDemand;
  @override
  ThreadFacetStamp? get currentProjection => _projection;
  _ExecutionIdentity? get _projectionIdentity {
    final source = _projection;
    return source == null ? null : (runtimeEpoch: source.runtimeEpoch, incarnation: source.incarnation);
  }
  bool get hasEvidenceDemand => _evidence.isNotEmpty;
  bool get isSelected => _selected;
  WorkspaceThreadRecord? get frozenThread => _thread;
  bool get isDisposed => _disposed;
  ConversationUiDemand? get uiDemand => _uiDemand;
  ConversationMetadataBorrow? reserveArchiveMetadata() => _metadata.reserve(allowNew: !_sealed);

  void bindUiDemand(int selectionGeneration) {
    final previous = _uiDemand;
    if (previous?.selectionGeneration == selectionGeneration) return;
    _uiDemand = ConversationUiDemand(selectionGeneration, nextAttempt());
  }

  ThreadFacetStamp? _sourceIdentity(ThreadFacetStamp source, {required bool baseline, required bool commit}) {
    if (_sealed) throw conversationCancelled;
    final previous = _projection;
    if (previous != null && source.runtimeEpoch != previous.runtimeEpoch) throw const StudioFailure(
      code: StudioFailureCode.runtimeStopped, message: 'A Session cannot adopt another runtime epoch.',
      retryable: false, correlationId: 'conversation-runtime-identity');
    if (previous != null && source.incarnation < previous.incarnation) throw const StudioFailure(
      code: StudioFailureCode.superseded, message: 'A late baseline belongs to a replaced projection.',
      retryable: true, correlationId: 'conversation-projection-identity');
    if (!baseline && (previous == null || source.incarnation != previous.incarnation)) throw const StudioFailure(
      code: StudioFailureCode.superseded, message: 'A change cannot establish a replacement Session projection.',
      retryable: true, correlationId: 'conversation-projection-baseline');
    if (commit) {
      _projection = source;
      for (final lease in _evidence) { lease._constrain(source); }
    }
    return previous;
  }

  void select(bool selected) {
    if (_sealed) { if (selected) throw conversationCancelled; return; }
    if (_selected == selected) return;
    _selected = selected;
    if (!selected) _uiDemand?.retired = true;
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
    final task = ConversationContextTask(threadId: threadId, attemptId: nextAttempt());
    _contextTask = task;
    final generation = ++_contextGeneration;
    task.start(budget: _budget, action: () async {
      for (final facet in ThreadFacet.values) {
        _checkContext(generation);
        if ((_selected || facet == ThreadFacet.execution) &&
            (facet != ThreadFacet.execution || !_hasCreatedExecution)) {
          _mirrors.synchronize(facet, const FacetSyncState(phase: FacetSyncPhase.connecting));
        }
      }
      await _resolveContext(generation);
    }, onFailure: (error, stack) {
      lastCause = error; lastStack = stack;
      if (!_sealed && generation == _contextGeneration) _contextFailed(error, stack);
    });
    return task.result;
  }
  void _checkContext(int generation) {
    if (_sealed || !_needsAny || generation != _contextGeneration) throw conversationCancelled;
  }
  Future<void> _resolveContext(int generation) async {
    _checkContext(generation);
    final thread = await _metadata.readForUi();
    _checkContext(generation);
    if (thread.id != threadId) throw const StudioFailure(code: StudioFailureCode.protocol,
      message: 'The metadata read returned another Thread.', retryable: false, correlationId: 'conversation-context-identity');
    final access = await _contextPort.readRecoveryAccess(thread);
    _checkContext(generation);
    switch (access) {
      case BlockedConversationRecovery(:final error): throw error;
      case UnknownConversationRecovery(:final error): throw error ?? const StudioFailure(
        code: StudioFailureCode.unavailable, message: 'The original Thread recovery access is unknown.',
        retryable: true, correlationId: 'conversation-recovery-unknown');
      case AllowedConversationRecovery(): break;
    }
    _mode = thread.parentThreadId != null && thread.role == 'planner' ? ThreadObservationMode.cold : ThreadObservationMode.live;
    _contextAllowed = true;
    _applyDemand();
  }
  void _contextFailed(Object error, StackTrace stack) {
    lastCause = error; lastStack = stack;
    if (_sealed) return;
    final failure = conversationFailure(error);
    for (final facet in ThreadFacet.values) {
      if ((_selected || facet == ThreadFacet.execution) &&
          (facet != ThreadFacet.execution || !_hasCreatedExecution)) {
        _mirrors.synchronize(facet, FacetSyncState(phase: FacetSyncPhase.failed, error: failure));
      }
    }
  }
  void _applyDemand() {
    if (_sealed) return;
    final mode = _mode ?? ThreadObservationMode.live;
    final ui = _selected && _contextAllowed;
    final generation = ++_demandGeneration;
    bool current() => !_sealed && generation == _demandGeneration;
    _feeds.demand(selected: ui, evidence: _executionDemand, mode: mode,
      isCurrent: current, executionSource: _feeds.executionHasBaseline ? _executionBinding : _wantedCreatedSource);
    if (!current()) return;
    _timeline.setDemand(ui);
  }
  CreatedInputExecutionBinding? get _wantedCreatedSource {
    for (final lease in _evidence) {
      if (lease._needsSource && lease._created != null) return lease._created;
    }
    return null;
  }
  bool get _hasCreatedExecution => _executionBinding != null || _wantedCreatedSource != null;
  @override
  Future<void> retry(ThreadFacet facet) {
    if (_sealed || !_needsAny) return Future.error(conversationCancelled);
    if (!_contextAllowed) return _loadContext();
    final phase = switch (facet) {
      ThreadFacet.execution => execution.value.sync.phase, ThreadFacet.metrics => metrics.value.sync.phase,
      ThreadFacet.context => context.value.sync.phase, ThreadFacet.configuration => configuration.value.sync.phase,
      ThreadFacet.authoring => authoring.value.sync.phase,
    };
    if (phase != FacetSyncPhase.failed && phase != FacetSyncPhase.reconnecting) return Future.value();
    if (facet == ThreadFacet.execution) {
      final previous = _feeds.executionAttemptId;
      _applyDemand();
      if (_feeds.executionAttemptId != null && _feeds.executionAttemptId != previous) return Future.value();
    }
    return _feeds.retry(facet);
  }
  @override
  Future<void> loadInteractionsPage({int limit = 32}) {
    if (readAdmissionClosed) return Future.error(conversationCancelled);
    return _index.load(limit: limit);
  }

  SubmissionExecutionLease retainForSubmission({required ThreadFacetStamp expectedOrigin}) {
    if (_sealed) throw conversationCancelled;
    if (expectedOrigin.facet != ThreadFacet.execution) throw _submissionConflict;
    if (readAdmissionClosed) throw _submissionConflict;
    final stamp = _readyExecutionStamp;
    if (stamp == null) throw _submissionConflict;
    if (!_sameProjection(expectedOrigin, stamp)) throw _submissionSuperseded;
    return _retainSubmission(stamp: stamp);
  }

  SubmissionExecutionLease retainForCreatedInput({required SubmitPromptReceipt receipt,
      required CreatedInputExecutionBinding binding}) {
    if (_sealed) throw conversationCancelled;
    if (receipt.threadId != threadId) throw _submissionConflict;
    if (receipt.inputId.trim().isEmpty || receipt.cursor < 0 || !_receiptDigest.hasMatch(receipt.requestDigest)) {
      throw const StudioFailure(code: StudioFailureCode.protocol,
        message: 'Created-input observation requires a valid native acceptance receipt.',
        retryable: false, correlationId: 'created-input-receipt');
    }
    if (binding.threadId != threadId || binding.inputId != receipt.inputId) throw _submissionConflict;
    if (binding.runtimeEpoch.isEmpty || binding.incarnation < 1) throw const StudioFailure(
      code: StudioFailureCode.protocol, message: 'The created-input source identity is invalid.',
      retryable: false, correlationId: 'created-input-source');
    final projection = _projection;
    if (projection != null && !binding.matches(projection)) throw _submissionSuperseded;
    final stamp = _readyExecutionStamp;
    for (final lease in _evidence) {
      final origin = lease._source;
      if (origin != null && (origin.runtimeEpoch != binding.runtimeEpoch ||
          origin.incarnation != binding.incarnation)) throw _submissionSuperseded;
      if (stamp == null && lease._created != null &&
          !identical(lease._created!.source, binding.source)) throw _submissionConflict;
    }
    return _retainSubmission(stamp: stamp, created: binding);
  }

  ThreadFacetStamp? get _readyExecutionStamp {
    final stamp = execution.value.stamp;
    final projection = _projection;
    return !_sealed && _feeds.executionHasBaseline &&
        execution.value.sync.phase == FacetSyncPhase.ready && execution.value.value != null &&
        stamp != null && stamp.facet == ThreadFacet.execution && projection != null &&
        _sameProjection(stamp, projection) ? stamp : null;
  }

  SubmissionExecutionLease _retainSubmission({required ThreadFacetStamp? stamp,
      CreatedInputExecutionBinding? created}) {
    if (_evidence.isEmpty) _evidenceReleased = Completer<void>();
    final lease = _SubmissionExecutionLease(threadId: threadId, attemptId: nextAttempt(),
      execution: execution, source: created == null ? _projectionIdentity :
        (runtimeEpoch: created.runtimeEpoch, incarnation: created.incarnation),
      created: created, release: _releaseEvidence);
    _evidence.add(lease);
    final attempt = _feeds.executionAttemptId;
    if (attempt != null && (stamp != null ||
        (created != null && identical(_executionBinding?.source, created.source)))) lease._bind(attempt);
    if (stamp != null && attempt != null) {
      lease._complete(attempt, stamp);
    }
    try {
      _applyDemand();
    } catch (error, stack) {
      lastCause = error; lastStack = stack;
      // Admission already transferred this lease. Return its failed ready and
      // release capability even when a synchronous notification failed.
      lease._fail(conversationFailure(error), stack);
    }
    return lease;
  }

  void _releaseEvidence(_SubmissionExecutionLease lease) {
    if (!_evidence.remove(lease)) return;
    if (_evidence.isEmpty) { _evidenceReleased?.complete(); _evidenceReleased = null; }
    if (!_selected && !_executionDemand) _contextGeneration++;
    try { if (!_sealed) _applyDemand(); } finally {
      if (!_selected && _evidence.isEmpty) _onUnused(this);
    }
  }

  void _executionAttempt(AttemptId attempt, CreatedInputExecutionBinding? binding) {
    _executionBinding = binding;
    var changed = false;
    for (final lease in List.of(_evidence)) { changed = lease._bind(attempt) || changed; }
    if (changed) _applyDemand();
  }
  void _executionBaseline(AttemptId attempt, ThreadFacetStamp stamp) {
    if (_sealed || _feeds.executionAttemptId != attempt || _readyExecutionStamp == null) return;
    var changed = false;
    for (final lease in List.of(_evidence)) { changed = lease._complete(attempt, stamp) || changed; }
    if (changed) _applyDemand();
  }
  void _executionFailed(StudioFailure error) {
    var changed = false;
    for (final lease in List.of(_evidence)) {
      changed = lease._fail(error) || changed;
      if (error.code == StudioFailureCode.superseded || error.code == StudioFailureCode.cancelled ||
          error.code == StudioFailureCode.runtimeStopped) changed = lease._invalidateCreated() || changed;
    }
    if (changed || (_executionBinding != null && _wantedCreatedSource == null)) _applyDemand();
  }
  void _checkExecutionSource(ThreadFacetStamp stamp) {
    final binding = _executionBinding;
    if (binding != null && (stamp.facet != ThreadFacet.execution || !binding.matches(stamp))) {
      throw _submissionSuperseded;
    }
  }
  void _incarnationChanged(ThreadFacetStamp previous) {
    var changed = false;
    for (final lease in List.of(_evidence)) {
      if (lease._source case final source? when _matchesIdentity(source, previous)) {
        changed = lease._fail(_submissionSuperseded) || changed;
        changed = lease._invalidateCreated() || changed;
      }
    }
    try { readOwners.retireOrigin(previous); } finally { if (changed) _applyDemand(); }
  }

  Future<CloseReport> retireUi({DateTime? deadline}) => closeRetiredUi(_uiDemand, deadline: deadline);
  void requestRetireUi(ConversationUiDemand? demand) {
    if (demand == null) return;
    demand.retired = true;
    if (!identical(_uiDemand, demand) || demand.retirementRequested) return;
    demand.retirementRequested = true;
    _selected = false;
    _contextGeneration++;
  }
  Future<CloseReport> closeRetiredUi(ConversationUiDemand? demand,
      {DateTime? deadline, bool retry = false}) {
    if (demand == null) return Future.value(CloseReport(unresolved: []));
    requestRetireUi(demand);
    final current = identical(_uiDemand, demand);
    final context = _contextTask;
    if (current && !_sealed && !demand.withdrawn) {
      demand.withdrawn = true;
      try { _applyDemand(); } catch (error, stack) { demand.recordFailure('conversationUiDemand', error, stack); }
    }
    return closeConversationUi(threadId: threadId, demand: demand,
      isCurrent: () => identical(_uiDemand, demand),
      closeScopes: () => readOwners.closeUi(demand, deadline: deadline, retry: retry), close: [
      if (current) () => _feeds.retireUi(retainExecution: _executionDemand, deadline: deadline, retry: retry),
      if (current) () => _timeline.close(deadline: deadline, retry: retry),
      if (current) () => _index.close(deadline: deadline, retry: retry),
      if (current) () => _metadata.close(deadline: deadline, retry: retry),
      if (current && context != null) () => context.close(deadline: deadline),
    ]);
  }
  void seal() {
    if (_sealed) return;
    _sealed = true; _selected = false; _contextGeneration++;
    _uiDemand?.retired = true;
    for (final lease in List.of(_evidence)) { lease._fail(conversationCancelled); }
    _feeds.seal(); _timeline.seal(); _index.seal(); readOwners.seal(); _metadata.seal();
  }
  Future<CloseReport> close({DateTime? deadline, bool retry = false}) async {
    seal();
    final closing = Future.wait([
      _feeds.close(deadline: deadline, retry: retry),
      _timeline.close(deadline: deadline, retry: retry),
      _index.close(deadline: deadline, retry: retry),
      readOwners.close(deadline: deadline, retry: retry),
      _metadata.close(deadline: deadline, retry: retry),
      if (_contextTask case final context?) context.close(deadline: deadline),
    ]);
    closing.ignore();
    final settled = Future.wait([
      if (_evidenceReleased case final evidence?) evidence.future,
    ]).then<void>((_) {});
    await observeConversationCompletion(settled, deadline);
    final reports = await closing;
    final unresolved = [for (final report in reports) ...report.unresolved,
      if (_uiDemand case final demand?) ...demand.report(threadId).unresolved,
      for (final lease in _evidence) UnresolvedResource(owner: 'conversation-evidence:$threadId',
        attemptId: lease.attemptId, issues: [_pendingIssue('operationDemandPending')]),
    ];
    if (unresolved.isEmpty && !_disposed) { _disposed = true; _mirrors.dispose(); }
    return conversationCloseReport(unresolved);
  }
  FeedCloseIssue _pendingIssue(String code) => FeedCloseIssue(diagnostic: StudioShutdownIssue(
    stage: 'conversationSession', code: code, message: 'The original Session work is still owned and in flight.',
    retryable: true, correlationId: 'conversation-session'), recovery: CleanupRecovery.awaitCompletion);
}

const _submissionConflict = StudioFailure(code: StudioFailureCode.conflict,
  message: 'Submission requires the original ready execution source.', retryable: false,
  correlationId: 'submission-execution-source');
const _submissionSuperseded = StudioFailure(code: StudioFailureCode.superseded,
  message: 'The original submission execution source has been replaced.', retryable: false,
  correlationId: 'submission-execution-superseded');
final _receiptDigest = RegExp(r'^sha256:[0-9a-f]{64}$');
bool _sameProjection(ThreadFacetStamp a, ThreadFacetStamp b) =>
    a.runtimeEpoch == b.runtimeEpoch && a.incarnation == b.incarnation;
typedef _ExecutionIdentity = ({String runtimeEpoch, int incarnation});
bool _matchesIdentity(_ExecutionIdentity a, ThreadFacetStamp b) =>
    a.runtimeEpoch == b.runtimeEpoch && a.incarnation == b.incarnation;

final class _SubmissionExecutionLease implements SubmissionExecutionLease {
  _SubmissionExecutionLease({required this.threadId, required this.attemptId,
    required this.execution, required _ExecutionIdentity? source, required CreatedInputExecutionBinding? created,
    required void Function(_SubmissionExecutionLease) release}) : _source = source, _created = created, _release = release {
    _ready.future.ignore();
  }
  @override
  final String threadId;
  @override
  final AttemptId attemptId;
  @override
  final ReadonlyLatestValue<ThreadExecutionState> execution;
  final void Function(_SubmissionExecutionLease) _release;
  final Completer<ThreadFacetStamp> _ready = Completer<ThreadFacetStamp>();
  _ExecutionIdentity? _source;
  final CreatedInputExecutionBinding? _created;
  AttemptId? _sourceAttempt;
  bool _needsSource = true;
  bool _released = false;
  @override
  Future<ThreadFacetStamp> get ready => _ready.future;
  void _constrain(ThreadFacetStamp source) {
    if (!_released && !_ready.isCompleted) _source ??=
      (runtimeEpoch: source.runtimeEpoch, incarnation: source.incarnation);
  }
  bool _bind(AttemptId attempt) {
    if (_released || _ready.isCompleted) return false;
    if (_sourceAttempt != null && _sourceAttempt != attempt) return _fail(_submissionSuperseded);
    _sourceAttempt = attempt;
    return false;
  }
  bool _complete(AttemptId attempt, ThreadFacetStamp stamp) {
    if (_released || _ready.isCompleted || _sourceAttempt != attempt) return false;
    final source = _source;
    if (source != null && !_matchesIdentity(source, stamp)) return _fail(_submissionSuperseded);
    _source = (runtimeEpoch: stamp.runtimeEpoch, incarnation: stamp.incarnation);
    _ready.complete(stamp);
    return false;
  }
  bool _fail(StudioFailure error, [StackTrace? stack]) {
    if (_ready.isCompleted) return false;
    _needsSource = false;
    _ready.completeError(error, stack);
    return true;
  }
  bool _invalidateCreated() {
    if (_created == null || !_needsSource) return false;
    _needsSource = false;
    return true;
  }
  @override
  void release() {
    if (_released) return;
    _released = true;
    _needsSource = false;
    _fail(conversationCancelled);
    _release(this);
  }
}
