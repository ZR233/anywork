import '../../../resources_ports.dart';
import '../domain/read_scopes.dart';
import '../domain/thread_identity.dart';
import 'connection_owner.dart';
import 'read_connections.dart';
import 'read_scope_owners.dart';
import 'session_ui_demand.dart';

/// Opening, unreturned and borrowed detail scopes all remain owned by this Session.
final class ConversationSessionReads {
  ConversationSessionReads({
    required this.threadId,
    required this.budget,
    required this.nextAttempt,
  });
  final String threadId;
  final ResourceBudget budget;
  final AttemptId Function() nextAttempt;
  final Map<
    ConversationReadScope,
    ({
      ThreadFacetStamp origin,
      ConversationUiDemand? demand,
      Object? evidence,
      bool Function() released,
      bool Function() closing,
      void Function() requestNativeClose,
      CloseReport Function() report,
    })
  >
  _scopes = {};
  bool _sealed = false;

  Future<S> open<
    C extends ConversationReadConnection,
    S extends PinnedConversationScope<C>
  >({
    required ThreadFacetStamp origin,
    required ConversationUiDemand demand,
    required Future<C> Function() open,
    required S Function(ConversationConnectionOwner<C>) build,
  }) => _open<C, S>(
    origin: origin,
    demand: demand,
    accepts: () => !demand.retired,
    open: open,
    build: build,
  );

  Future<TurnScopeOwner> openExecutionTurn({
    required Object evidence,
    required ThreadFacetStamp origin,
    required TurnReadRef reference,
    required bool Function() accepts,
    required Future<TurnReadConnection> Function() open,
  }) => _open<TurnReadConnection, TurnScopeOwner>(
    origin: origin,
    evidence: evidence,
    accepts: accepts,
    open: open,
    build: (owner) => TurnScopeOwner(
      owner,
      origin,
      expectedRevision: reference.revision,
      expectedThreadId: threadId,
    ),
  );

  Future<S> _open<
    C extends ConversationReadConnection,
    S extends PinnedConversationScope<C>
  >({
    required ThreadFacetStamp origin,
    ConversationUiDemand? demand,
    Object? evidence,
    required bool Function() accepts,
    required Future<C> Function() open,
    required S Function(ConversationConnectionOwner<C>) build,
  }) {
    if (_sealed || !accepts()) throw conversationCancelled;
    _scopes.removeWhere((_, entry) => entry.released());
    if (_scopes.length >= 8)
      throw const StudioFailure(
        code: StudioFailureCode.overloaded,
        message: 'The Thread already has eight owned detail scopes.',
        retryable: true,
        correlationId: 'thread-read-scopes',
        details: StudioFailureDetails.resourceLimit(
          resource: 'threadReadScope',
          capacity: 8,
        ),
      );
    final ConversationConnectionOwner<C> owner;
    try {
      owner = ConversationConnectionOwner<C>(
        label: 'thread-read:$threadId',
        attemptId: nextAttempt(),
        budget: budget,
        kind: ResourceKind.readModel,
        requestClose: (c) => c.requestClose(),
        close: (c) => c.close(),
        retryClose: (c) => c.retryClose(),
      );
    } on ResourceBudgetExceeded catch (error) {
      throw error.failure;
    }
    final S scope;
    try {
      scope = build(owner);
    } catch (error, stack) {
      owner.start(() => Future.error(error, stack));
      owner.close().ignore();
      rethrow;
    }
    _scopes[scope] = (
      origin: origin,
      demand: demand,
      evidence: evidence,
      released: () => owner.released,
      closing: () => owner.isClosing,
      requestNativeClose: () => owner.requestNativeClose(),
      report: owner.report,
    );
    owner.start(() async {
      if (_sealed || !accepts()) throw conversationCancelled;
      final permit = budget.acquire(
        ResourceKind.pendingOperation,
        owner: 'thread-read-open:$threadId',
      );
      try {
        if (_sealed || !accepts()) throw conversationCancelled;
        return await open();
      } finally {
        permit.release();
      }
    });
    if (_sealed || !accepts()) {
      owner.requestClose();
      owner.close().ignore();
    }
    return owner.opened.then(
      (_) => scope,
      onError: (Object error, StackTrace stack) {
        owner.requestClose();
        owner.close().ignore();
        Error.throwWithStackTrace(conversationFailure(error), stack);
      },
    );
  }

  bool hasEvidenceReads(Object evidence) => _scopes.values.any(
    (entry) => identical(entry.evidence, evidence) && !entry.released(),
  );

  CloseReport evidenceReport(Object evidence) => conversationCloseReport([
    for (final entry in _scopes.values)
      if (identical(entry.evidence, evidence) && !entry.released())
        ...entry.report().unresolved,
  ]);

  void requestCloseEvidence(Object evidence) {
    for (final entry in List.of(_scopes.entries)) {
      if (identical(entry.value.evidence, evidence)) entry.key.requestClose();
    }
  }

  /// Join each already-opened evidence handle without denying the reads this
  /// evidence already admitted. Used when the caller that must join them is the
  /// same context that admitted them.
  void requestNativeCloseEvidence(Object evidence) {
    for (final entry in List.of(_scopes.values)) {
      if (identical(entry.evidence, evidence)) entry.requestNativeClose();
    }
  }

  Future<CloseReport> closeEvidence(
    Object evidence, {
    DateTime? deadline,
    bool retry = false,
  }) async {
    requestCloseEvidence(evidence);
    final scopes = [
      for (final entry in _scopes.entries)
        if (identical(entry.value.evidence, evidence)) entry.key,
    ];
    await Future.wait([
      for (final scope in scopes)
        retry
            ? scope.retryCleanup(deadline: deadline)
            : scope.close(deadline: deadline),
    ]);
    _scopes.removeWhere((_, entry) => entry.released());
    return evidenceReport(evidence);
  }

  void retireOrigin(ThreadFacetStamp previous) {
    for (final entry in List.of(_scopes.entries)) {
      final origin = entry.value.origin;
      if (origin.runtimeEpoch == previous.runtimeEpoch &&
          origin.incarnation == previous.incarnation) {
        entry.key.requestClose();
        entry.key.close().ignore();
      }
    }
  }

  void seal() {
    if (_sealed) return;
    _sealed = true;
    for (final scope in List.of(_scopes.keys)) {
      scope.requestClose();
    }
  }

  Future<CloseReport> closeUi(
    ConversationUiDemand demand, {
    DateTime? deadline,
    bool retry = false,
  }) async {
    demand.retired = true;
    final scopes = [
      for (final entry in _scopes.entries)
        if (identical(entry.value.demand, demand)) entry.key,
    ];
    await Future.wait([
      for (final scope in scopes)
        retry
            ? scope.retryCleanup(deadline: deadline)
            : scope.close(deadline: deadline),
    ]);
    _scopes.removeWhere((_, entry) => entry.released());
    // A synchronous admission which was reentered by retirement still registers
    // its cancelled open in this same map. Include its actual current report.
    return conversationCloseReport([
      for (final entry in _scopes.values)
        if (identical(entry.demand, demand)) ...entry.report().unresolved,
    ]);
  }

  Future<CloseReport> close({
    DateTime? deadline,
    bool retry = false,
    Set<Object> joinedEvidence = const {},
  }) async {
    seal();
    // Exact command work joins its own reads after its real dispatch settles.
    // One Session retry must not retry those same handles again in this pass.
    final scopes = [
      for (final entry in _scopes.entries)
        if (!joinedEvidence.contains(entry.value.evidence)) entry.key,
    ];
    final reports = await Future.wait([
      for (final scope in scopes)
        retry
            ? scope.retryCleanup(deadline: deadline)
            : scope.close(deadline: deadline),
    ]);
    _scopes.removeWhere((_, entry) => entry.released());
    return CloseReport(
      unresolved: [for (final report in reports) ...report.unresolved],
    );
  }

  Future<CloseReport> retryCleanup({
    DateTime? deadline,
    Set<Object> joinedEvidence = const {},
    ConversationUiDemand? joinedUi,
  }) async {
    final scopes = [
      for (final entry in _scopes.entries)
        if (entry.value.closing() &&
            !entry.value.released() &&
            (joinedUi == null || !identical(entry.value.demand, joinedUi)) &&
            !joinedEvidence.contains(entry.value.evidence))
          entry.key,
    ];
    final reports = await Future.wait([
      for (final scope in scopes) scope.retryCleanup(deadline: deadline),
    ]);
    _scopes.removeWhere((_, entry) => entry.released());
    return conversationCloseReport([
      for (final report in reports) ...report.unresolved,
    ]);
  }
}
