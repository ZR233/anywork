import '../../../drafts.dart' show SubmitPromptReceipt;
import '../../../operations_ports.dart';
import '../../../resources_ports.dart';
import '../../../workspace.dart' show WorkspaceState;
import '../../../workspace_ports.dart'
    show
        WorkspaceArchiveCapturePort,
        WorkspaceProjectArchiveCapture,
        WorkspaceThreadArchiveCapture;
import '../domain/conversation_activation_failure.dart';
import '../domain/conversation_repository.dart';
import '../domain/thread_identity.dart';
import 'connection_owner.dart';
import 'conversation_archive_capture.dart';
import 'conversation_command_port.dart';
import 'conversation_demand.dart';
import 'conversation_mirror.dart';
import 'conversation_observation_port.dart';
import 'session_owner.dart';
import 'timeline_port.dart';

({
  ConversationRepository repository,
  ConversationDemand demand,
  WorkspaceArchiveCapturePort archive,
})
createConversationRepository({
  required ConversationObservationPort port,
  required ConversationContextPort context,
  required ConversationCommandPort commands,
  required TimelineTransport timeline,
  required ResourceBudget budget,
  required OperationRecorder operations,
}) {
  final permit = budget.acquire(
    ResourceKind.readModel,
    owner: 'conversation-repository',
  );
  try {
    final owner = _ConversationRepository(
      port,
      context,
      commands,
      timeline,
      budget,
      operations,
      permit,
    );
    return (repository: owner, demand: owner, archive: owner);
  } catch (_) {
    permit.release();
    rethrow;
  }
}

final class _ConversationRepository
    implements
        ConversationRepository,
        ConversationDemand,
        WorkspaceArchiveCapturePort {
  _ConversationRepository(
    this.port,
    this.context,
    this.commands,
    this.timeline,
    this.budget,
    this.operations,
    ResourcePermit permit,
  ) : _permit = permit,
      _active = ConversationMirror(
        null,
        budget: budget,
        owner: 'conversation-active',
      ),
      _activationFailure = ConversationMirror(
        null,
        budget: budget,
        owner: 'conversation-activation-failure',
      );
  final ConversationObservationPort port;
  final ConversationContextPort context;
  final ConversationCommandPort commands;
  final TimelineTransport timeline;
  final ResourceBudget budget;
  final OperationRecorder operations;
  final ResourcePermit _permit;
  final ConversationMirror<ConversationSession?> _active;
  final ConversationMirror<ConversationActivationFailure?> _activationFailure;
  ({ConversationActivationFailure failure, Object cause, StackTrace stack})?
  _activationEvidence;
  final Map<String, ConversationSessionOwner> _current = {};
  final Set<ConversationSessionOwner> _owned = {};
  ConversationSessionOwner? _selected;
  String? _selectionThread;
  int _selectionGeneration = -1;
  int _attemptSequence = 0;
  bool _selectionNeedsOpen = false;
  bool _sealed = false;
  bool _disposed = false;
  @override
  ReadonlyLatestValue<ConversationSession?> get active => _active.readonly;
  @override
  ReadonlyLatestValue<ConversationActivationFailure?> get activationFailure =>
      _activationFailure.readonly;
  AttemptId _nextAttempt() => AttemptId(++_attemptSequence);
  @override
  ConversationSession? existingSession(String threadId) => _current[threadId];
  @override
  ConversationSession session(String threadId) {
    if (_sealed) throw conversationCancelled;
    try {
      return _session(threadId);
    } on ResourceBudgetExceeded catch (error, stack) {
      Error.throwWithStackTrace(error.failure, stack);
    }
  }

  ConversationSessionOwner _submissionSession(ConversationSession exact) {
    if (_sealed) throw conversationCancelled;
    for (final owner in _owned) {
      if (!identical(owner, exact)) continue;
      if (!identical(_current[owner.threadId], owner))
        throw const StudioFailure(
          code: StudioFailureCode.superseded,
          message: 'The original submission Session has been replaced.',
          retryable: false,
          correlationId: 'submission-session-replaced',
        );
      return owner;
    }
    throw const StudioFailure(
      code: StudioFailureCode.conflict,
      message: 'The submission Session belongs to another Repository.',
      retryable: false,
      correlationId: 'submission-session-owner',
    );
  }

  @override
  SubmissionExecutionLease retainForSubmission(
    ConversationSession exact, {
    required ThreadFacetStamp expectedOrigin,
  }) =>
      _submissionSession(exact)
          .retainForSubmission(expectedOrigin: expectedOrigin);
  @override
  SubmissionExecutionLease retainForCreatedInput(
    ConversationSession exact, {
    required SubmitPromptReceipt receipt,
    required CreatedInputExecutionSource source,
  }) {
    final owner = _submissionSession(exact);
    final binding = CreatedInputExecutionBinding(source);
    // Source property access cannot transfer admission to a reentrant replacement.
    _submissionSession(exact);
    return owner.retainForCreatedInput(receipt: receipt, binding: binding);
  }

  ConversationSessionOwner _session(String threadId) {
    final existing = _current[threadId];
    if (existing != null) return existing;
    final permit = budget.acquire(
      ResourceKind.readModel,
      owner: 'session:$threadId',
    );
    final ConversationSessionOwner owner;
    try {
      owner = ConversationSessionOwner(
        threadId: threadId,
        observationPort: port,
        contextPort: context,
        budget: budget,
        readModelPermit: permit,
        operations: operations,
        commands: commands,
        timelinePort: timeline,
        nextAttempt: _nextAttempt,
        onUnused: _retireUnused,
      );
    } catch (_) {
      // No source is opened by construction; this is its only resource permit.
      // Release can synchronously notify capacity observers and replace demand.
      permit.release();
      rethrow;
    }
    _owned.add(owner);
    _current[threadId] = owner;
    return owner;
  }

  static const _invalidGeneration = StudioFailure(
    code: StudioFailureCode.invalidArgument,
    message: 'Selection generation must be nonnegative.',
    retryable: false,
    correlationId: 'conversation-selection',
  );
  static const _supersededActivation = StudioFailure(
    code: StudioFailureCode.superseded,
    message: 'The original activation demand is no longer current.',
    retryable: false,
    correlationId: 'conversation-activation-superseded',
  );

  bool _matchesSelection(String? threadId, int generation, bool needsOpen) =>
      !_sealed &&
      _selectionThread == threadId &&
      _selectionGeneration == generation &&
      _selectionNeedsOpen == needsOpen;

  void _clearActivationFailure() {
    _activationEvidence = null;
    if (_activationFailure.value != null) _activationFailure.publish(null);
  }

  void _activate(String threadId, int generation) {
    if (!_matchesSelection(threadId, generation, false) || _selected != null)
      return;
    final ConversationSessionOwner owner;
    try {
      owner = _session(threadId);
    } catch (error, stack) {
      if (!_matchesSelection(threadId, generation, false) || _selected != null)
        return;
      final failure = ConversationActivationFailure(
        threadId: threadId,
        selectionGeneration: generation,
        error: conversationFailure(error),
      );
      _activationEvidence = (failure: failure, cause: error, stack: stack);
      // Nothing from this attempt is published after a reentrant retry/select.
      _activationFailure.publish(failure);
      return;
    }
    if (!_matchesSelection(threadId, generation, false) || _selected != null) {
      _retireUnused(owner);
      return;
    }
    _selected = owner;
    owner.bindUiDemand(generation);
    // The Session now exists. Its context/facet errors belong to that Session,
    // never to the pre-Session activation failure slot.
    _active.publish(owner);
    if (_matchesSelection(threadId, generation, false) &&
        identical(_selected, owner))
      owner.select(true);
  }

  @override
  void retryActivation({
    required String threadId,
    required int selectionGeneration,
  }) {
    if (_sealed) throw conversationCancelled;
    if (selectionGeneration < 0) throw _invalidGeneration;
    if (!_matchesSelection(threadId, selectionGeneration, false))
      throw _supersededActivation;
    if (_selected != null) return;
    final evidence = _activationEvidence;
    if (evidence == null ||
        !identical(evidence.failure, _activationFailure.value) ||
        evidence.failure.threadId != threadId ||
        evidence.failure.selectionGeneration != selectionGeneration)
      return;
    _clearActivationFailure();
    if (_matchesSelection(threadId, selectionGeneration, false) &&
        _selected == null)
      _activate(threadId, selectionGeneration);
  }

  @override
  void select({
    required String? threadId,
    required bool needsOpen,
    required int selectionGeneration,
  }) {
    if (_sealed) throw conversationCancelled;
    if (selectionGeneration < 0) throw _invalidGeneration;
    if (selectionGeneration < _selectionGeneration) return;
    if (selectionGeneration == _selectionGeneration) {
      if (_selectionThread == threadId && _selectionNeedsOpen == needsOpen)
        return;
      if (_selectionThread != threadId)
        throw const StudioFailure(
          code: StudioFailureCode.conflict,
          message:
              'The same selection generation cannot describe another demand.',
          retryable: false,
          correlationId: 'conversation-selection-generation',
        );
    }
    final previous = _selected;
    _selected = null;
    _selectionThread = threadId;
    _selectionNeedsOpen = needsOpen;
    _selectionGeneration = selectionGeneration;
    // Remove this concrete old Session before synchronous notification. A→B→A
    // reentry allocates a new A instead of borrowing a retiring same-ID handle.
    if (previous != null) {
      previous.retireStopAdmission();
      if (identical(_current[previous.threadId], previous))
        _current.remove(previous.threadId);
    }
    try {
      _clearActivationFailure();
      if (!_matchesSelection(threadId, selectionGeneration, needsOpen)) return;
      _active.publish(null);
    } finally {
      if (previous != null) {
        previous.select(false);
        _retireUnused(previous);
      }
    }
    if (!_matchesSelection(threadId, selectionGeneration, needsOpen) ||
        threadId == null ||
        needsOpen)
      return;
    _activate(threadId, selectionGeneration);
  }

  void _retireUnused(ConversationSessionOwner owner) {
    if (owner.isSelected) return;
    if (owner.hasEvidenceDemand && !_sealed) {
      owner.retireUi().ignore();
      return;
    }
    owner.close().then((report) {
      if (report.complete) {
        _owned.remove(owner);
        if (identical(_current[owner.threadId], owner))
          _current.remove(owner.threadId);
      }
    }).ignore();
  }

  @override
  WorkspaceProjectArchiveCapture captureProject(
    String projectId, {
    required WorkspaceState frozenSelection,
  }) {
    if (_sealed) throw conversationCancelled;
    final owned = List.of(_owned);
    final generation = _selectionGeneration;
    return ConversationProjectArchiveCapture(
      projectId,
      frozenSelection,
      _nextAttempt(),
      [
        for (final owner in owned)
          ConversationArchiveSession(
            owner,
            generation,
            prepareMembership: true,
          ),
      ],
      _retireCapturedUi,
    );
  }

  @override
  WorkspaceThreadArchiveCapture captureThread(
    String threadId, {
    required WorkspaceState frozenSelection,
  }) {
    if (_sealed) throw conversationCancelled;
    final owned = List.of(_owned);
    final generation = _selectionGeneration;
    return ConversationThreadArchiveCapture(
      threadId,
      frozenSelection,
      _nextAttempt(),
      [
        for (final owner in owned)
          ConversationArchiveSession(
            owner,
            generation,
            prepareMembership: false,
          ),
      ],
      _retireCapturedUi,
    );
  }

  Future<CloseReport> _retireCapturedUi(
    ConversationArchiveSession original, {
    DateTime? deadline,
    bool retry = false,
  }) async {
    final owner = original.owner;
    final demand = original.demand;
    // Fence the captured token before publication can reenter selection/open.
    owner.requestRetireUi(demand);
    if (_selectionGeneration == original.repositoryGeneration &&
        identical(owner.uiDemand, demand)) {
      if (identical(_current[owner.threadId], owner))
        _current.remove(owner.threadId);
      if (identical(_selected, owner)) {
        _selected = null;
        try {
          _active.publish(null);
        } catch (error, stack) {
          demand?.recordFailure('conversationArchiveSelection', error, stack);
        }
      }
    }
    final ui = await owner.closeRetiredUi(
      demand,
      deadline: deadline,
      retry: retry,
    );
    if (!ui.complete ||
        owner.isSelected ||
        owner.hasEvidenceDemand ||
        !identical(owner.uiDemand, demand))
      return ui;
    // The existing unused-Session rule: no operation demand remains. Do not
    // retain an otherwise Clean archived Session's read-model permit forever.
    final closed = await owner.close(deadline: deadline, retry: retry);
    if (closed.complete) {
      _owned.remove(owner);
      if (identical(_current[owner.threadId], owner))
        _current.remove(owner.threadId);
    }
    return closed;
  }

  @override
  Future<CloseReport> retire(String threadId, {DateTime? deadline}) async {
    final retiring = _owned
        .where((owner) => owner.threadId == threadId)
        .toList();
    for (final owner in retiring) {
      owner.retireStopAdmission();
      if (identical(_current[threadId], owner)) _current.remove(threadId);
    }
    final selected = _selected;
    if (selected != null && selected.threadId == threadId) {
      _selected = null;
      _active.publish(null);
    }
    for (final owner in retiring) {
      owner.select(false);
    }
    final reports = await Future.wait([
      for (final owner in retiring)
        owner.hasEvidenceDemand && !_sealed
            ? owner.retireUi(deadline: deadline)
            : owner.close(deadline: deadline),
    ]);
    return CloseReport(
      unresolved: [for (final report in reports) ...report.unresolved],
    );
  }

  @override
  void retrySelected(String threadId) {
    if (_sealed) throw conversationCancelled;
    final selected = _selected;
    if (selected == null ||
        selected.threadId != threadId ||
        _selectionThread != threadId ||
        _selectionNeedsOpen)
      return;
    for (final facet in ThreadFacet.values) {
      selected.retry(facet).ignore();
    }
  }

  @override
  void seal() {
    if (_sealed) return;
    _sealed = true;
    _selected = null;
    _current.clear();
    for (final owner in List.of(_owned)) {
      owner.seal();
    }
    _clearActivationFailure();
    _active.publish(null);
    _active.close();
    _activationFailure.close();
  }

  @override
  Future<CloseReport> close({DateTime? deadline}) async {
    seal();
    final reports = await Future.wait([
      for (final owner in List.of(_owned)) owner.close(deadline: deadline),
    ]);
    return _finishCleanup(reports);
  }

  @override
  Future<CloseReport> retryCleanup({DateTime? deadline}) async {
    // A running Repository keeps its selection and healthy owners. Each
    // Session continues only cleanup whose admission was already retired.
    final reports = await Future.wait([
      for (final owner in List.of(_owned))
        owner.retryCleanup(deadline: deadline),
    ]);
    return _finishCleanup(reports);
  }

  CloseReport _finishCleanup(List<CloseReport> reports) {
    final unresolved = [for (final report in reports) ...report.unresolved];
    _owned.removeWhere((owner) => owner.isDisposed);
    _current.removeWhere((_, owner) => owner.isDisposed);
    if (_sealed && _owned.isEmpty && unresolved.isEmpty && !_disposed) {
      _disposed = true;
      _active.close();
      _activationFailure.close();
      _permit.release();
    }
    return CloseReport(unresolved: unresolved);
  }
}
